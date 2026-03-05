// RBAC role assignments for the PostgreSQL HA stack (current resource group scope).
//
// 1. Storage Blob Data Contributor  →  UAMI → backup storage
//    CNPG uses inheritFromAzureAD for barman-cloud backups.
//
// 2. Monitoring Data Reader  →  Grafana MSI → Azure Monitor workspace
//    Allows the Grafana instance to read Managed Prometheus metrics.
//
// Note: The Network Contributor role for the AKS node resource group is
// handled separately in nodeRgRoleAssignment.bicep (different RG scope).

param storageAccountName string
param monitorWorkspaceName string
param uamiPrincipalId string
param grafanaPrincipalId string

var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var monitoringDataReaderRoleId = 'b0d8363b-2dab-4ec3-9ef3-d15f7bcc08c4'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' existing = {
  name: monitorWorkspaceName
}

// 1. Storage Blob Data Contributor: UAMI → backup storage
resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, uamiPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// 2. Monitoring Data Reader: Grafana MSI → Azure Monitor workspace
resource monitoringDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(monitorWorkspace.id, grafanaPrincipalId, monitoringDataReaderRoleId)
  scope: monitorWorkspace
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', monitoringDataReaderRoleId)
    principalId: grafanaPrincipalId
    principalType: 'ServicePrincipal'
  }
}
