// Azure Key Vault for storing Airflow secrets (storage account credentials).
// Improvement over README: uses RBAC authorization instead of access policies.
// Purge protection enabled to comply with security best practices.

param name string
param location string
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    // RBAC authorization replaces legacy access policies (README used --enable-rbac-authorization false)
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // Purge protection prevents accidental or malicious deletion of secrets
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output name string = keyVault.name
