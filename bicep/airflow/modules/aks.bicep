// AKS cluster for Apache Airflow.
// - Standard tier for SLA-backed control plane
// - 3 nodes across 3 availability zones for HA
// - Azure CNI networking
// - OIDC issuer + workload identity for pod-level Azure auth
// - Blob CSI driver for log persistence
// - Azure RBAC for Kubernetes authorization (improvement over README)

param clusterName string
param location string
param dnsPrefix string
param nodeVmSize string = 'Standard_DS4_v2'
param nodeCount int = 3
param kubernetesVersion string = ''
param tags object = {}

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion != '' ? kubernetesVersion : null

    agentPoolProfiles: [
      {
        name: 'nodepool1'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        osDiskType: 'Managed'
        availabilityZones: ['1', '2', '3']
        mode: 'System'
        enableAutoScaling: false
      }
    ]

    networkProfile: {
      networkPlugin: 'azure'
    }

    // OIDC issuer enables federated identity (workload identity)
    oidcIssuerProfile: {
      enabled: true
    }

    // Workload identity allows pods to authenticate to Azure services
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // Blob CSI driver required for the Airflow log persistent volume
    storageProfile: {
      blobCSIDriver: {
        enabled: true
      }
    }

    // Automatic upgrade keeps nodes secure with minimal operator effort
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }

    // Azure RBAC replaces Kubernetes RBAC for cluster authorization (improvement over README)
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
  }
}

output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerUrl
// Kubelet identity is used for AcrPull role assignment
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
