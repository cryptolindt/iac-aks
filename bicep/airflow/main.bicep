// ============================================================
// Apache Airflow on AKS – Infrastructure
// Subscription-scoped deployment: creates resource group and
// all dependent Azure resources in a single pass.
//
// Improvements over README:
//   • Key Vault RBAC authorization (not access policies)
//   • Purge protection on Key Vault
//   • Azure RBAC for AKS Kubernetes authorization
//   • Storage account key auto-populated into Key Vault
//   • Federated credential created inline (no manual step)
// ============================================================
targetScope = 'subscription'

// ── Parameters ───────────────────────────────────────────────
@description('Azure region for all resources.')
param location string = 'canadacentral'

@description('8-char suffix appended to globally unique resource names.')
param suffix string = substring(uniqueString(subscription().id, location), 0, 8)

@description('Resource group name.')
param resourceGroupName string = 'apache-airflow-rg'

@description('AKS cluster name.')
param clusterName string = 'apache-airflow-aks'

@description('User-assigned managed identity name (used by ESO).')
param identityName string = 'airflow-identity-${suffix}'

@description('Key Vault name (globally unique, max 24 chars).')
param keyVaultName string = 'kv-airflow-${suffix}'

@description('ACR name (globally unique, lowercase alphanumeric only).')
param acrName string = 'acr${suffix}airflow'

@description('Storage account name for Airflow logs (globally unique).')
param storageAccountName string = 'stairflow${suffix}'

@description('Blob container name for Airflow logs.')
param logsContainerName string = 'airflow-logs'

@description('Kubernetes namespace for Airflow.')
param airflowNamespace string = 'airflow'

@description('Kubernetes service account name for Airflow / ESO.')
param serviceAccountName string = 'airflow'

@description('Object ID of the deployment principal (needs Key Vault Secrets Officer).')
param deployerObjectId string

@description('Tags applied to all resources.')
param tags object = {
  application: 'apache-airflow'
  environment: 'production'
  managedBy: 'bicep'
}

// ── Resource Group ────────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ── Managed Identity (ESO) ────────────────────────────────────
module identity 'modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: identityName
    location: location
    tags: tags
  }
}

// ── Key Vault ─────────────────────────────────────────────────
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: keyVaultName
    location: location
    tags: tags
  }
}

// ── ACR ───────────────────────────────────────────────────────
module acr 'modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    name: acrName
    location: location
    tags: tags
  }
}

// ── Storage Account + KV Secrets ─────────────────────────────
// Depends on Key Vault so RBAC officer role is granted first.
module storage 'modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    storageAccountName: storageAccountName
    containerName: logsContainerName
    location: location
    keyVaultName: keyVaultName
    tags: tags
  }
  dependsOn: [keyVault, roleAssignments]  // Officer role must exist before writing secrets
}

// ── AKS Cluster ───────────────────────────────────────────────
module aks 'modules/aks.bicep' = {
  name: 'aks'
  scope: rg
  params: {
    clusterName: clusterName
    location: location
    dnsPrefix: 'airflow-${suffix}'
    tags: tags
  }
}

// ── RBAC Role Assignments ─────────────────────────────────────
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  scope: rg
  params: {
    acrName: acrName
    keyVaultName: keyVaultName
    kubeletIdentityObjectId: aks.outputs.kubeletIdentityObjectId
    esoIdentityPrincipalId: identity.outputs.principalId
    deployerObjectId: deployerObjectId
  }
  dependsOn: [acr, keyVault, aks]
}

// ── Federated Credential (ESO workload identity) ──────────────
module federatedCredential 'modules/federatedCredential.bicep' = {
  name: 'federatedCredential'
  scope: rg
  params: {
    identityName: identityName
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
    namespace: airflowNamespace
    serviceAccountName: serviceAccountName
  }
  dependsOn: [identity, aks]
}

// ── Outputs ───────────────────────────────────────────────────
output resourceGroupName string = rg.name
output clusterName string = aks.outputs.clusterName
output acrLoginServer string = acr.outputs.loginServer
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.keyVaultUri
output storageAccountName string = storage.outputs.storageAccountName
output identityClientId string = identity.outputs.clientId
output oidcIssuerUrl string = aks.outputs.oidcIssuerUrl
