// Parameter file for Apache Airflow on AKS infrastructure.
// Override any value here before deploying.
//
// Deploy with:
//   az deployment sub create \
//     --location canadacentral \
//     --template-file bicep/airflow/main.bicep \
//     --parameters bicep/airflow/main.bicepparam
//
// Get your Object ID with:
//   az ad signed-in-user show --query id -o tsv

using 'main.bicep'

// Required: Object ID of the user or service principal running the deployment.
// Must have permissions to create role assignments at the subscription scope.
param deployerObjectId = '<your-object-id>'

// Optional overrides (defaults are defined in main.bicep)
param location = 'canadacentral'
param resourceGroupName = 'apache-airflow-rg'
param airflowNamespace = 'airflow'
param serviceAccountName = 'airflow'
param logsContainerName = 'airflow-logs'

param tags = {
  application: 'apache-airflow'
  environment: 'production'
  managedBy: 'bicep'
}
