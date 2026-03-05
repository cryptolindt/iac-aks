#!/usr/bin/env bash
# =============================================================================
# Deploy Apache Airflow on AKS
#
# Stages:
#   1. Deploy Azure infrastructure via Bicep
#   2. Pull AKS credentials
#   3. Apply Kubernetes manifests (namespace, service account, secrets, PV/PVC)
#   4. Install External Secrets Operator via Helm
#   5. Install Apache Airflow via Helm
#
# Prerequisites:
#   - Azure CLI logged in (az login)
#   - kubectl installed
#   - helm installed
#   - envsubst installed (gettext)
#   - bicep/airflow/main.bicepparam updated with your deployerObjectId
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCATION="${LOCATION:-canadacentral}"
BICEP_PARAM="${REPO_ROOT}/bicep/airflow/main.bicepparam"
K8S_DIR="${REPO_ROOT}/k8s/airflow"

# ── 1. Deploy infrastructure ─────────────────────────────────────────────────
echo "==> Validating Bicep deployment (what-if)..."
az deployment sub what-if \
  --location "${LOCATION}" \
  --template-file "${REPO_ROOT}/bicep/airflow/main.bicep" \
  --parameters "${BICEP_PARAM}" \
  --no-pretty-print

echo ""
read -rp "Proceed with deployment? [y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }

echo "==> Deploying Airflow infrastructure..."
DEPLOYMENT_OUTPUT=$(az deployment sub create \
  --location "${LOCATION}" \
  --template-file "${REPO_ROOT}/bicep/airflow/main.bicep" \
  --parameters "${BICEP_PARAM}" \
  --query "properties.outputs" \
  --output json)

# Parse outputs
MY_RESOURCE_GROUP_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.resourceGroupName.value')
MY_CLUSTER_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.clusterName.value')
MY_ACR_LOGIN_SERVER=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.acrLoginServer.value')
MY_KEYVAULT_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.keyVaultName.value')
KEYVAULT_URL=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.keyVaultUri.value')
AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.storageAccountName.value')
IDENTITY_CLIENT_ID=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.identityClientId.value')
OIDC_URL=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.oidcIssuerUrl.value')

echo "  Resource Group : ${MY_RESOURCE_GROUP_NAME}"
echo "  Cluster        : ${MY_CLUSTER_NAME}"
echo "  ACR            : ${MY_ACR_LOGIN_SERVER}"
echo "  Key Vault      : ${MY_KEYVAULT_NAME}"

# ── 2. AKS credentials ────────────────────────────────────────────────────────
echo "==> Getting AKS credentials..."
az aks get-credentials \
  --resource-group "${MY_RESOURCE_GROUP_NAME}" \
  --name "${MY_CLUSTER_NAME}" \
  --overwrite-existing

# ── 3. Import images (optional; skip if already done) ────────────────────────
if [[ "${SKIP_IMAGE_IMPORT:-false}" != "true" ]]; then
  ACR_NAME="${MY_ACR_LOGIN_SERVER%%.*}"
  echo "==> Importing container images into ACR ${ACR_NAME}..."
  bash "${SCRIPT_DIR}/import-images.sh" "${ACR_NAME}"
fi

# ── 4. Kubernetes manifests ───────────────────────────────────────────────────
export SERVICE_ACCOUNT_NAMESPACE="airflow"
export SERVICE_ACCOUNT_NAME="airflow"
export AKS_AIRFLOW_NAMESPACE="airflow"
export AKS_AIRFLOW_LOGS_STORAGE_CONTAINER_NAME="airflow-logs"
export AKS_AIRFLOW_LOGS_STORAGE_SECRET_NAME="storage-account-credentials"
export TENANT_ID=$(az account show --query tenantId -o tsv)
export MY_RESOURCE_GROUP_NAME
export AKS_AIRFLOW_LOGS_STORAGE_ACCOUNT_NAME
export IDENTITY_CLIENT_ID
export KEYVAULT_URL

echo "==> Applying Kubernetes manifests..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
envsubst < "${K8S_DIR}/serviceaccount.yaml" | kubectl apply -f -
envsubst < "${K8S_DIR}/pv.yaml"             | kubectl apply -f -
kubectl apply -f "${K8S_DIR}/pvc.yaml"

# ── 5. External Secrets Operator ─────────────────────────────────────────────
echo "==> Installing External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  --namespace "${AKS_AIRFLOW_NAMESPACE}" \
  --create-namespace \
  --set installCRDs=true \
  --wait

echo "==> Applying SecretStore and ExternalSecret..."

envsubst < "${K8S_DIR}/secretstore.yaml"    | kubectl apply -f -
envsubst < "${K8S_DIR}/externalsecret.yaml" | kubectl apply -f -

# ── 6. Apache Airflow ─────────────────────────────────────────────────────────
ACR_NAME="${MY_ACR_LOGIN_SERVER%%.*}"
AIRFLOW_VALUES=$(mktemp /tmp/airflow_values.XXXX.yaml)
cat > "${AIRFLOW_VALUES}" << EOF
images:
  airflow:
    repository: ${MY_ACR_LOGIN_SERVER}/airflow
    tag: 3.0.2
    pullPolicy: IfNotPresent
  pod_template:
    repository: ${MY_ACR_LOGIN_SERVER}/airflow
    tag: 3.0.2
    pullPolicy: IfNotPresent
  flower:
    repository: ${MY_ACR_LOGIN_SERVER}/airflow
    tag: 3.0.2
    pullPolicy: IfNotPresent
  statsd:
    repository: ${MY_ACR_LOGIN_SERVER}/statsd-exporter
    tag: v0.28.0
    pullPolicy: IfNotPresent
  pgbouncer:
    repository: ${MY_ACR_LOGIN_SERVER}/airflow
    tag: airflow-pgbouncer-2025.03.05-1.23.1
    pullPolicy: IfNotPresent
  pgbouncerExporter:
    repository: ${MY_ACR_LOGIN_SERVER}/airflow
    tag: airflow-pgbouncer-exporter-2025.03.05-0.18.0
    pullPolicy: IfNotPresent
  gitSync:
    repository: ${MY_ACR_LOGIN_SERVER}/git-sync
    tag: v4.3.0
    pullPolicy: IfNotPresent

executor: "KubernetesExecutor"

env:
  - name: ENVIRONMENT
    value: dev

extraEnv: |
  - name: AIRFLOW__CORE__DEFAULT_TIMEZONE
    value: 'America/New_York'

postgresql:
  enabled: true
  image:
    registry: ${MY_ACR_LOGIN_SERVER}
    repository: postgresql
    tag: 16.1.0-debian-11-r15

pgbouncer:
  enabled: true

dags:
  gitSync:
    enabled: true
    repo: https://github.com/donhighmsft/airflowexamples.git
    branch: main
    rev: HEAD
    depth: 1
    maxFailures: 0
    subPath: "dags"

logs:
  persistence:
    enabled: true
    existingClaim: pvc-airflow-logs
    storageClassName: azureblob-fuse-premium

triggerer:
  logGroomerSidecar:
    enabled: false
scheduler:
  logGroomerSidecar:
    enabled: false
workers:
  logGroomerSidecar:
    enabled: false
EOF

echo "==> Installing Apache Airflow (chart 1.15.0)..."
helm repo add apache-airflow https://airflow.apache.org
helm repo update

helm upgrade --install airflow apache-airflow/airflow \
  --version 1.15.0 \
  --namespace "${AKS_AIRFLOW_NAMESPACE}" \
  --create-namespace \
  -f "${AIRFLOW_VALUES}" \
  --debug

rm -f "${AIRFLOW_VALUES}"

echo ""
echo "✓ Airflow deployment complete."
echo "  Access the UI: kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow"
echo "  Credentials  : admin / admin (change immediately)"
