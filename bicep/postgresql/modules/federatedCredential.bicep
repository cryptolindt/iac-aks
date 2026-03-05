// Federated identity credential for CNPG.
// Binds the 'postgres' Kubernetes service account (auto-created by the CNPG
// operator with the same name as the cluster) to the UAMI so PostgreSQL pods
// can authenticate to Azure Blob Storage without any client secrets.

param identityName string
param oidcIssuerUrl string
param namespace string
param pgClusterName string
param credentialName string = 'cnpg-fedcred'

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: '${identityName}/${credentialName}'
  properties: {
    issuer: oidcIssuerUrl
    // CNPG creates a service account named after the cluster in the PostgreSQL namespace
    subject: 'system:serviceaccount:${namespace}:${pgClusterName}'
    audiences: ['api://AzureADTokenExchange']
  }
}
