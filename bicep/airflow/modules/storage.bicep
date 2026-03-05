// Azure Storage Account (ZRS) for Airflow task logs.
// Blob container for logs is created automatically.
// Storage account name and key are stored in Key Vault so the
// External Secrets Operator can sync them into a Kubernetes secret
// consumed by the Azure Blob CSI driver for the static log PV.

param storageAccountName string
param containerName string
param location string
param keyVaultName string
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true  // Required: Azure Blob CSI static PV uses key-based secret
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource logsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Retrieve the existing Key Vault to attach secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Store storage account name in Key Vault (synced by ESO into K8s secret)
resource secretAccountName 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-NAME'
  properties: {
    value: storageAccount.name
  }
}

// Store storage account key in Key Vault
resource secretAccountKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'AKS-AIRFLOW-LOGS-STORAGE-ACCOUNT-KEY'
  properties: {
    value: storageAccount.listKeys().keys[0].value
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
