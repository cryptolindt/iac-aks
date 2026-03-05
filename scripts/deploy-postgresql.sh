#!/usr/bin/env bash
# =============================================================================
# Deploy Highly Available PostgreSQL on AKS (CloudNativePG)
#
# Stages:
#   1. Deploy Azure infrastructure via Bicep
#   2. Pull AKS credentials and create namespaces
#   3. Install kube-prometheus-stack (PodMonitor CRDs + recording rules)
#   4. Install CNPG operator via Helm
#   5. Create bootstrap app user secret
#   6. Deploy CNPG Cluster CRD
#   7. Apply Azure Monitor PodMonitor
#
# Prerequisites:
#   - Azure CLI logged in
#   - kubectl installed
#   - helm installed
#   - kubectl krew + cnpg plugin installed (optional, for cnpg commands)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCATION="${LOCATION:-canadacentral}"
BICEP_PARAM="${REPO_ROOT}/bicep/postgresql/main.bicepparam"

# ── 1. Deploy infrastructure ─────────────────────────────────────────────────
echo "==> Validating Bicep deployment (what-if)..."
az deployment sub what-if \
  --location "${LOCATION}" \
  --template-file "${REPO_ROOT}/bicep/postgresql/main.bicep" \
  --parameters "${BICEP_PARAM}" \
  --no-pretty-print

echo ""
read -rp "Proceed with deployment? [y/N] " confirm
[[ "${confirm,,}" == "y" ]] || { echo "Aborted."; exit 0; }

echo "==> Deploying PostgreSQL infrastructure..."
DEPLOYMENT_OUTPUT=$(az deployment sub create \
  --location "${LOCATION}" \
  --template-file "${REPO_ROOT}/bicep/postgresql/main.bicep" \
  --parameters "${BICEP_PARAM}" \
  --query "properties.outputs" \
  --output json)

# Parse outputs
RESOURCE_GROUP_NAME=$(echo "${DEPLOYMENT_OUTPUT}"                  | jq -r '.resourceGroupName.value')
AKS_PRIMARY_CLUSTER_NAME=$(echo "${DEPLOYMENT_OUTPUT}"             | jq -r '.clusterName.value')
PG_PRIMARY_STORAGE_ACCOUNT_NAME=$(echo "${DEPLOYMENT_OUTPUT}"      | jq -r '.storageAccountName.value')
AKS_UAMI_WORKLOAD_CLIENTID=$(echo "${DEPLOYMENT_OUTPUT}"           | jq -r '.identityClientId.value')
AKS_PRIMARY_CLUSTER_PUBLICIP_ADDRESS=$(echo "${DEPLOYMENT_OUTPUT}" | jq -r '.publicIpAddress.value')

# These are set in main.bicepparam / main.bicep defaults
PG_NAMESPACE="${PG_NAMESPACE:-cnpg-database}"
PG_SYSTEM_NAMESPACE="${PG_SYSTEM_NAMESPACE:-cnpg-system}"
# Derive the cluster name from the deployment (assumes default naming)
PG_PRIMARY_CLUSTER_NAME=$(az deployment sub show \
  --name "$(az deployment sub list --query "[?contains(name,'postgresql')].[name]" -o tsv | head -1)" \
  --query "properties.parameters.pgClusterName.value" -o tsv 2>/dev/null || echo "pg-primary-cnpg")

echo "  Resource Group  : ${RESOURCE_GROUP_NAME}"
echo "  Cluster         : ${AKS_PRIMARY_CLUSTER_NAME}"
echo "  Public IP       : ${AKS_PRIMARY_CLUSTER_PUBLICIP_ADDRESS}"

# ── 2. AKS credentials + namespaces ──────────────────────────────────────────
echo "==> Getting AKS credentials..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${AKS_PRIMARY_CLUSTER_NAME}" \
  --output none

echo "==> Creating namespaces..."
kubectl create namespace "${PG_NAMESPACE}"       --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "${PG_SYSTEM_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── 3. kube-prometheus-stack (PodMonitor CRDs + CNPG recording rules) ────────
echo "==> Installing kube-prometheus-stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install \
  --namespace "${PG_NAMESPACE}" \
  -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/docs/src/samples/monitoring/kube-stack-config.yaml \
  prometheus-community \
  prometheus-community/kube-prometheus-stack \
  --kube-context="${AKS_PRIMARY_CLUSTER_NAME}"

# ── 4. CNPG operator ──────────────────────────────────────────────────────────
echo "==> Installing CNPG operator..."
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update

helm upgrade --install cnpg \
  --namespace "${PG_SYSTEM_NAMESPACE}" \
  --create-namespace \
  --kube-context="${AKS_PRIMARY_CLUSTER_NAME}" \
  cnpg/cloudnative-pg

echo "==> Waiting for CNPG deployment to be ready..."
kubectl wait deployment/cnpg-cloudnative-pg \
  --namespace "${PG_SYSTEM_NAMESPACE}" \
  --for=condition=Available \
  --timeout=120s

# ── 5. Bootstrap app user secret ─────────────────────────────────────────────
echo "==> Creating bootstrap app user secret..."
PG_DATABASE_APPUSER_SECRET=$(openssl rand -base64 16)
kubectl create secret generic db-user-pass \
  --from-literal=username=app \
  --from-literal=password="${PG_DATABASE_APPUSER_SECRET}" \
  --namespace "${PG_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  App user password stored in secret 'db-user-pass' (namespace: ${PG_NAMESPACE})"

# ── 6. CNPG ConfigMap + CNPG Cluster CRD ─────────────────────────────────────
echo "==> Applying CNPG controller ConfigMap..."

kubectl apply --namespace "${PG_NAMESPACE}" -f "${REPO_ROOT}/k8s/postgresql/configmap.yaml"

# Derive storage class; default to Premium SSD
POSTGRES_STORAGE_CLASS="${POSTGRES_STORAGE_CLASS:-managed-csi-premium}"

echo "==> Deploying PostgreSQL cluster (storage class: ${POSTGRES_STORAGE_CLASS})..."

envsubst < "${REPO_ROOT}/k8s/postgresql/cluster.yaml" | kubectl apply --namespace "${PG_NAMESPACE}" -f -

# ── 7. PodMonitor for Azure Monitor (Managed Prometheus) ─────────────────────
echo "==> Applying PodMonitors..."

envsubst < "${REPO_ROOT}/k8s/postgresql/podmonitor.yaml" | kubectl apply --namespace "${PG_NAMESPACE}" -f -

echo ""
echo "✓ PostgreSQL deployment complete."
echo "  Check pod status: kubectl get pods -n ${PG_NAMESPACE} -l cnpg.io/cluster=${PG_PRIMARY_CLUSTER_NAME}"
echo "  Public IP        : ${AKS_PRIMARY_CLUSTER_PUBLICIP_ADDRESS}"
