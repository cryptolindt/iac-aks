// RBAC role assignments for the Airflow stack.
//
// 1. AcrPull  →  AKS kubelet identity → ACR
//    Allows worker nodes to pull images from the private registry.
//
// 2. Key Vault Secrets User  →  UAMI (ESO) → Key Vault
//    Allows the External Secrets Operator to read secrets.
//
// 3. Key Vault Secrets Officer  →  Deployer → Key Vault
//    Allows the deployment principal to write the storage account secrets
//    (required because Key Vault uses RBAC authorization, not access policies).

param acrName string
param keyVaultName string
param kubeletIdentityObjectId string
param esoIdentityPrincipalId string
param deployerObjectId string

// Well-known Azure built-in role definition IDs
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var kvSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e0'
var kvSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// 1. AcrPull: AKS kubelet identity → ACR
resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, kubeletIdentityObjectId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: kubeletIdentityObjectId
    principalType: 'ServicePrincipal'
  }
}

// 2. Key Vault Secrets User: ESO managed identity → Key Vault
resource kvSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, esoIdentityPrincipalId, kvSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUserRoleId)
    principalId: esoIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 3. Key Vault Secrets Officer: deployer → Key Vault (needed to write secrets via listKeys)
resource kvSecretsOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, deployerObjectId, kvSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', kvSecretsOfficerRoleId)
    principalId: deployerObjectId
    principalType: 'User'
  }
}
