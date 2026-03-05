// ============================================================
// Highly Available PostgreSQL on AKS – Infrastructure
// Subscription-scoped deployment: creates resource group and
// all supporting Azure resources for the CNPG operator.
//
// Improvements over README:
//   • Azure RBAC for AKS Kubernetes authorization
//   • Managed Prometheus + Grafana integration wired at deploy time
//   • Storage account uses workload identity (no shared keys)
//   • Network Contributor scoped correctly to node resource group
//   • Federated credential created inline
// ============================================================
targetScope = 'subscription'

// ── Parameters ───────────────────────────────────────────────
@description('Azure region for all resources.')
param location string = 'canadacentral'

@description('8-char suffix appended to globally unique resource names.')
param suffix string = substring(uniqueString(subscription().id, location), 0, 8)

@description('Resource group name.')
param resourceGroupName string = 'rg-cnpg-${suffix}'

@description('AKS cluster name.')
param clusterName string = 'aks-primary-cnpg-${suffix}'

@description('Name for the AKS-managed node resource group.')
param nodeResourceGroupName string = 'rg-cnpg-primary-aksmanaged-${suffix}'

@description('User-assigned managed identity name.')
param identityName string = 'mi-aks-cnpg-${suffix}'

@description('Storage account name for PostgreSQL backups.')
param storageAccountName string = 'hacnpgpsa${suffix}'

@description('Blob container name for backups.')
param backupsContainerName string = 'backups'

@description('Azure Managed Grafana name.')
param grafanaName string = 'grafana-cnpg-${suffix}'

@description('Azure Monitor workspace name (Managed Prometheus).')
param monitorWorkspaceName string = 'amw-cnpg-${suffix}'

@description('Log Analytics workspace name.')
param logAnalyticsName string = 'ala-cnpg-${suffix}'

@description('Public IP name for PostgreSQL ingress.')
param publicIpName string = 'aks-primary-cnpg-${suffix}-pip'

@description('DNS label prefix for the PostgreSQL public IP.')
param pgDnsPrefix string = 'a${substring(uniqueString(subscription().id, location, 'pg'), 0, 11)}'

@description('Kubernetes namespace for the PostgreSQL cluster.')
param pgNamespace string = 'cnpg-database'

@description('CNPG cluster name (also the service account name created by the operator).')
param pgClusterName string = 'pg-primary-cnpg-${suffix}'

@description('Kubernetes version for the AKS cluster.')
param kubernetesVersion string = '1.32'

@description('Your client IP for API server authorized IP ranges (leave empty to allow all).')
param apiServerClientIp string = ''

@description('Tags applied to all resources.')
param tags object = {
  application: 'postgresql-ha'
  environment: 'production'
  managedBy: 'bicep'
}

// ── Resource Group ────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ── Managed Identity (CNPG) ───────────────────────────────────
module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: identityName
    location: location
    tags: tags
  }
}

// ── Backup Storage ────────────────────────────────────────────
module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    storageAccountName: storageAccountName
    containerName: backupsContainerName
    location: location
    tags: tags
  }
}

// ── Monitoring Stack ──────────────────────────────────────────
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    grafanaName: grafanaName
    monitorWorkspaceName: monitorWorkspaceName
    logAnalyticsName: logAnalyticsName
    location: location
    tags: tags
  }
}

// ── AKS Cluster ───────────────────────────────────────────────
module aks 'modules/aks.bicep' = {
  name: 'aks'
  scope: rg
  params: {
    clusterName: clusterName
    nodeResourceGroupName: nodeResourceGroupName
    location: location
    dnsPrefix: 'cnpg-${suffix}'
    identityId: identity.outputs.identityId
    monitorWorkspaceId: monitoring.outputs.monitorWorkspaceId
    grafanaId: monitoring.outputs.grafanaId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    kubernetesVersion: kubernetesVersion
    apiServerAuthorizedIpRanges: apiServerClientIp != '' ? ['${apiServerClientIp}/32'] : []
    tags: tags
  }
}

// ── Role Assignments (current RG scope) ──────────────────────
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  scope: rg
  params: {
    storageAccountName: storageAccountName
    monitorWorkspaceName: monitorWorkspaceName
    uamiPrincipalId: identity.outputs.principalId
    grafanaPrincipalId: monitoring.outputs.grafanaPrincipalId
  }
  dependsOn: [storage, monitoring]
}

// ── Network Contributor on AKS Node Resource Group ───────────
// The node RG is created by AKS provisioning; reference it as existing.
resource nodeRg 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: nodeResourceGroupName
  dependsOn: [aks]
}

module nodeRgRoleAssignment 'modules/nodeRgRoleAssignment.bicep' = {
  name: 'nodeRgRoleAssignment'
  scope: nodeRg
  params: {
    uamiPrincipalId: identity.outputs.principalId
  }
  dependsOn: [aks]
}

// ── Public IP for PostgreSQL Ingress ──────────────────────────
// Created in the node resource group so AKS can reference it
// directly in the LoadBalancer service annotation.
module publicIp 'modules/publicIp.bicep' = {
  name: 'publicIp'
  scope: nodeRg
  params: {
    name: publicIpName
    location: location
    dnsLabelPrefix: pgDnsPrefix
    tags: tags
  }
  dependsOn: [aks]
}

// ── Federated Credential (CNPG workload identity) ─────────────
module federatedCredential 'modules/federatedCredential.bicep' = {
  name: 'federatedCredential'
  scope: rg
  params: {
    identityName: identityName
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
    namespace: pgNamespace
    pgClusterName: pgClusterName
  }
  dependsOn: [identity, aks]
}

// ── Outputs ───────────────────────────────────────────────────
output resourceGroupName string = rg.name
output clusterName string = aks.outputs.clusterName
output nodeResourceGroup string = aks.outputs.nodeResourceGroup
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
output storageAccountName string = storage.outputs.storageAccountName
output identityClientId string = identity.outputs.clientId
output grafanaName string = grafanaName
output monitorWorkspaceName string = monitorWorkspaceName
output publicIpAddress string = publicIp.outputs.publicIpAddress
output pgDnsFqdn string = publicIp.outputs.fqdn
