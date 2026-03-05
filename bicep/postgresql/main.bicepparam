// Parameter file for the highly available PostgreSQL on AKS infrastructure.
//
// Deploy with:
//   az deployment sub create \
//     --location canadacentral \
//     --template-file bicep/postgresql/main.bicep \
//     --parameters bicep/postgresql/main.bicepparam
//
// Get your public IP:
//   dig +short myip.opendns.com @resolver3.opendns.com

using 'main.bicep'

param location = 'canadacentral'
param kubernetesVersion = '1.32'

// Restrict API server access to your machine's public IP.
// Leave empty to allow all (not recommended for production).
param apiServerClientIp = ''  // e.g. '203.0.113.42'

param pgNamespace = 'cnpg-database'

param tags = {
  application: 'postgresql-ha'
  environment: 'production'
  managedBy: 'bicep'
}
