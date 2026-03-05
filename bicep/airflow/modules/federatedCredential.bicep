// Federated identity credential binding the External Secrets Operator
// Kubernetes service account to the Azure user-assigned managed identity.
// This enables workload identity so ESO pods can obtain Azure AD tokens
// without storing any client secrets.

param identityName string
param oidcIssuerUrl string
param namespace string
param serviceAccountName string
param credentialName string = 'external-secret-operator'

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  name: '${identityName}/${credentialName}'
  properties: {
    issuer: oidcIssuerUrl
    subject: 'system:serviceaccount:${namespace}:${serviceAccountName}'
    audiences: ['api://AzureADTokenExchange']
  }
}
