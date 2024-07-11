using 'main.bicep'

param hubVirtualNetworkId =  '/subscriptions/8e40a08f-f236-4265-aae4-3be0fdd0442f/resourceGroups/rg-hub-dev-gwc-001/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev-gwc-001'

param logAnalyticsWorkspaceId =  '1a0b8d0e-2543-4dc5-b8a9-44e1be4df844'

param otherSubnetsConfig = {
  subnets: [
    {
      name: 'snet-custom-{workloadName}-{env}'
      addressPrefix: '10.1.6.0/24'
      // No optional properties specified
    }  
  ]
}
