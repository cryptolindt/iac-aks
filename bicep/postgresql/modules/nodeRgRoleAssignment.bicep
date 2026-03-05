// Network Contributor role assignment scoped to the AKS node resource group.
// This module must be deployed WITH scope set to the node resource group so
// the UAMI can manage load balancer resources for PostgreSQL service endpoints.
//
// Deployed from main.bicep after the AKS cluster is provisioned:
//   module nodeRgRole 'modules/nodeRgRoleAssignment.bicep' = {
//     scope: nodeResourceGroup
//     ...
//   }

param uamiPrincipalId string

var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e8'

resource networkContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, uamiPrincipalId, networkContributorRoleId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}
