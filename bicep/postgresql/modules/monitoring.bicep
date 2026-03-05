// Monitoring stack for the PostgreSQL cluster:
//   • Azure Managed Grafana  – dashboards
//   • Azure Monitor Workspace – Managed Prometheus metrics
//   • Log Analytics Workspace – Container Insights logs

param grafanaName string
param monitorWorkspaceName string
param logAnalyticsName string
param location string
param tags object = {}

// Azure Managed Grafana
resource grafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    zoneRedundancy: 'Enabled'
    publicNetworkAccess: 'Enabled'
  }
}

// Azure Monitor Workspace (Managed Prometheus)
resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  tags: tags
}

// Log Analytics Workspace (Container Insights)
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output grafanaId string = grafana.id
output grafanaPrincipalId string = grafana.identity.principalId
output monitorWorkspaceId string = monitorWorkspace.id
output logAnalyticsId string = logAnalytics.id
