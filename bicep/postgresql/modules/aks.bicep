// AKS cluster for the highly available PostgreSQL workload.
//
// Node pools:
//   • systempool  – Standard_D2s_v3, 2-3 nodes, autoscale
//   • postgres    – Standard_D4s_v3, 3-6 nodes, autoscale
//                   labelled workload=postgres for CNPG nodeSelector
//
// Networking: Azure CNI overlay with Cilium dataplane
// Observability: Azure Monitor metrics (Managed Prometheus) + Container Insights

param clusterName string
param nodeResourceGroupName string
param location string
param dnsPrefix string
param identityId string               // UAMI assigned to the cluster
param monitorWorkspaceId string       // Azure Monitor workspace for Managed Prometheus
param grafanaId string                // Managed Grafana linked to AKS metrics
param logAnalyticsId string           // Log Analytics for Container Insights
param kubernetesVersion string = '1.32'
param systemVmSize string = 'Standard_D2s_v3'
param postgresVmSize string = 'Standard_D4s_v3'
param apiServerAuthorizedIpRanges array = []  // Pass your client IP for security
param tags object = {}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  // Assign the UAMI so CNPG pods can authenticate to Azure services
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: nodeResourceGroupName

    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 2
        minCount: 2
        maxCount: 3
        vmSize: systemVmSize
        osType: 'Linux'
        osDiskType: 'Managed'
        availabilityZones: ['1', '2', '3']
        mode: 'System'
        enableAutoScaling: true
      }
      {
        name: 'postgres'
        count: 3
        minCount: 3
        maxCount: 6
        vmSize: postgresVmSize
        osType: 'Linux'
        osDiskType: 'Managed'
        availabilityZones: ['1', '2', '3']
        mode: 'User'
        enableAutoScaling: true
        // Label used by CNPG topologySpreadConstraints and nodeSelector
        nodeLabels: {
          workload: 'postgres'
        }
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
    }

    oidcIssuerProfile: {
      enabled: true
    }

    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // Azure RBAC for Kubernetes authorization
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }

    // Managed Prometheus integration
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
      containerInsights: {
        enabled: true
        logAnalyticsWorkspaceResourceId: logAnalyticsId
      }
    }

    // Grafana linked to the Azure Monitor workspace
    addonProfiles: {
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsId
          useAADAuth: 'true'
        }
      }
    }

    apiServerAccessProfile: {
      authorizedIPRanges: apiServerAuthorizedIpRanges
    }

    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }
  }
}

output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerUrl
output nodeResourceGroup string = aksCluster.properties.nodeResourceGroup
