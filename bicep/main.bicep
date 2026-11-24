// Same platform as terraform/azure, written in Bicep. Compiled to ARM in bicep/main.json.
targetScope = 'resourceGroup'

@allowed(['dev', 'staging', 'prod'])
param environment string
@minLength(3)
@maxLength(10)
param prefix string = 'iislab'
param location string = resourceGroup().location
param appServiceSku string = 'B1'
param publisherName string = 'iis-release-lab'
param publisherEmail string = 'owner@example.com'
@description('Public IPs allowed to reach the storage account. Everything else is denied.')
param allowedIps array = []

var name = '${prefix}-${environment}'
var busName = 'sb-${name}'
var tags = {
  environment: environment
  managed_by: 'bicep'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${take(replace(name, '-', ''), 20)}'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices, Logging, Metrics'
      ipRules: [for ip in allowedIps: { value: ip, action: 'Allow' }]
    }
  }
}

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${name}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${name}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${name}'
  location: location
  tags: tags
  sku: { name: appServiceSku }
  properties: {}
}

// Windows web app: runs on IIS.
resource site 'Microsoft.Web/sites@2023-12-01' = {
  name: 'app-${name}'
  location: location
  tags: tags
  kind: 'app'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      alwaysOn: true
      healthCheckPath: '/health.html'
      appSettings: [
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'ServiceBusNamespace', value: '${busName}.servicebus.windows.net' }
      ]
    }
  }
}

resource func 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-${name}'
  location: location
  tags: tags
  kind: 'functionapp'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'dotnet-isolated' }
      ]
    }
  }
}

module bus 'modules/servicebus.bicep' = {
  name: 'servicebus'
  params: {
    name: busName
    location: location
    tags: tags
    senderPrincipalId: site.identity.principalId
    receiverPrincipalId: func.identity.principalId
  }
}

resource apim 'Microsoft.ApiManagement/service@2022-08-01' = {
  name: 'apim-${name}'
  location: location
  tags: tags
  sku: { name: 'Consumption', capacity: 0 }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

output webAppUrl string = 'https://${site.properties.defaultHostName}'
output queue string = bus.outputs.queueName
