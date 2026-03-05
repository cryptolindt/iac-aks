// User-assigned managed identity for CNPG (CloudNativePG).
// Used by PostgreSQL pods to authenticate to Azure Blob Storage
// for WAL archiving and backups via workload identity federation.

param name string
param location string
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
  tags: tags
}

output identityId string = identity.id
output principalId string = identity.properties.principalId
output clientId string = identity.properties.clientId
output name string = identity.name
