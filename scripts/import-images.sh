#!/usr/bin/env bash
# =============================================================================
# Import all required container images into Azure Container Registry.
# Call from deploy-airflow.sh or run standalone:
#
#   ACR_NAME=myregistry bash scripts/import-images.sh
#   bash scripts/import-images.sh myregistry
#
# Images are imported from Docker Hub, Quay, and registry.k8s.io.
# Running this saves AKS nodes from pulling public images on every deployment.
# =============================================================================
set -euo pipefail

ACR_NAME="${1:-${ACR_NAME:?'Pass ACR name as first arg or set ACR_NAME env var'}}"

import() {
  local source="$1" image="$2"
  echo "  Importing ${source} -> ${image}..."
  az acr import \
    --name "${ACR_NAME}" \
    --source "${source}" \
    --image "${image}" \
    --force 2>/dev/null || echo "    (already exists, skipping)"
}

echo "==> Importing images into ACR: ${ACR_NAME}"

# Apache Airflow
import "docker.io/apache/airflow:3.0.2"                                          "airflow:3.0.2"
import "docker.io/apache/airflow:airflow-pgbouncer-2025.03.05-1.23.1"            "airflow:airflow-pgbouncer-2025.03.05-1.23.1"
import "docker.io/apache/airflow:airflow-pgbouncer-exporter-2025.03.05-0.18.0"   "airflow:airflow-pgbouncer-exporter-2025.03.05-0.18.0"

# Sidecar utilities
import "quay.io/prometheus/statsd-exporter:v0.28.0"   "statsd-exporter:v0.28.0"
import "registry.k8s.io/git-sync/git-sync:v4.3.0"     "git-sync:v4.3.0"

# PostgreSQL (bundled Helm sub-chart – not recommended for production)
import "docker.io/bitnamilegacy/postgresql:16.1.0-debian-11-r15"  "postgresql:16.1.0-debian-11-r15"

echo ""
echo "✓ All images imported into ${ACR_NAME}."
echo "  Login server: $(az acr show --name "${ACR_NAME}" --query loginServer -o tsv)"
