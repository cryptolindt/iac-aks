// Standard zone-redundant static public IP for exposing PostgreSQL cluster
// endpoints (primary read/write + read-only replicas) via an Azure Load Balancer.

param name string
param location string
param dnsLabelPrefix string
param tags object = {}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
