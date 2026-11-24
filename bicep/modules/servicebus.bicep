@description('Namespace name.')
param name string
param location string
param tags object = {}

@description('Principal that may send messages (the web app identity).')
param senderPrincipalId string
@description('Principal that may receive messages (the function identity).')
param receiverPrincipalId string

resource ns 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Standard' }
  properties: { minimumTlsVersion: '1.2' }
}

resource orders 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: ns
  name: 'orders'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
  }
}

// Azure Service Bus Data Sender and Data Receiver. Managed identity only, no connection strings.
var senderRole = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var receiverRole = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'

resource sender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ns
  name: guid(ns.id, senderPrincipalId, senderRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', senderRole)
    principalId: senderPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource receiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: ns
  name: guid(ns.id, receiverPrincipalId, receiverRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', receiverRole)
    principalId: receiverPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output namespaceHost string = '${ns.name}.servicebus.windows.net'
output queueName string = orders.name
