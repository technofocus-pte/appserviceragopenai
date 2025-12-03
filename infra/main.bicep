@description('The location used for all resources')
param location string = resourceGroup().location

@description('Name used for the deployment environment')
param environmentName string

@description('Unique suffix for naming resources')
param resourceToken string = uniqueString(resourceGroup().id, environmentName)

@description('Tags that will be applied to all resources')
param tags object = {
  'azd-env-name': environmentName
}

@description('Principal ID of the user running the deployment (for role assignments)')
param userPrincipalId string = ''

// ----------------------------------------------------
// App Service and configuration
// ----------------------------------------------------

@description('Name of the App Service for hosting the Blazor app')
param appServiceName string = 'app-${resourceToken}'

@description('App Service Plan SKU')
@allowed([
  'B1'
  'B2'
  'B3'
  'P1v2'
  'P2v2'
  'P3v2'
])
param appServicePlanSku string = 'B1'

var appServicePlanLocation = 'canadacentral'

// Create App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'plan-${resourceToken}'
  location: appServicePlanLocation
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'app'
  properties: {
    reserved: true
  }
}

// Create App Service
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: appServiceName
  location: appServicePlanLocation
  tags: union(tags, {
    'azd-service-name': 'web'  // Add tag required by azd for deployment
  })
  identity: {
    type: 'SystemAssigned' // Add system-assigned managed identity for App Service
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      // Configure Linux container with .NET 8.0
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true
      // Enable application logging
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      requestTracingEnabled: true
      logsDirectorySizeLimit: 35
      appSettings: [
        {
          name: 'OpenAIEndpoint'
          value: openAiAccount.properties.endpoint
        }
        {
          name: 'OpenAIGptDeployment'
          value: openAiGptDeploymentName
        }
        {
          name: 'OpenAIEmbeddingDeployment'
          value: openAiEmbeddingDeploymentName
        }
        {
          name: 'SearchServiceUrl'
          value: 'https://${searchService.name}.search.windows.net'
        }
        {
          name: 'SearchIndexName'
          value: searchIndexName
        }
        {
          name: 'SystemPrompt'
          value: 'You are an AI assistant that helps people find information from their documents. Always cite your sources using the document title.'
        }
        // App Service Logging Configuration
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'ASPNETCORE_LOGGING__CONSOLE__DISABLECOLORS'
          value: 'true'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__DEFAULT'
          value: 'Information'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__MICROSOFT'
          value: 'Warning'
        }
        {
          name: 'ASPNETCORE_LOGGING__LOGLEVEL__MICROSOFT.ASPNETCORE'
          value: 'Warning'
        }
      ]
    }
  }
}

// ----------------------------------------------------
// Azure OpenAI service
// ----------------------------------------------------

@description('Name of the Azure OpenAI service')
param openAiServiceName string = 'ai-${resourceToken}'

@description('Azure OpenAI service SKU')
param openAiSkuName string = 'S0'

@description('GPT model deployment name')
param openAiGptDeploymentName string = 'gpt-4o-mini'

@description('GPT model name')
param openAiGptModelName string = 'gpt-4o-mini'

@description('GPT model version')
param openAiGptModelVersion string = '2025-04-14'

@description('Embedding model deployment name')
param openAiEmbeddingDeploymentName string = 'text-embedding-ada-002'

@description('Embedding model name')
param openAiEmbeddingModelName string = 'text-embedding-ada-002'

@description('Embedding model version')
param openAiEmbeddingModelVersion string = '2'

// Create OpenAI service
resource openAiAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAiServiceName
  location: location
  tags: tags
  kind: 'OpenAI'
  identity: {
    type: 'SystemAssigned' // Add system-assigned managed identity for OpenAI
  }
  sku: {
    name: openAiSkuName
  }
  properties: {
    customSubDomainName: openAiServiceName // Required for Microsoft Entra ID authentication
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Deploy GPT model
resource openAiGptDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: openAiGptDeploymentName
  sku: {
    name: 'DataZoneStandard'
    capacity: 20
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiGptModelName
      version: openAiGptModelVersion
    }
  }
}

// Deploy Embedding model
resource openAiEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAiAccount
  name: openAiEmbeddingDeploymentName
  dependsOn: [
    openAiGptDeployment // Add explicit dependency to ensure sequential deployment
  ]
  sku: {
    name: 'Standard'
    capacity: 20
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiEmbeddingModelName
      version: openAiEmbeddingModelVersion
    }
  }
}

// ----------------------------------------------------
// Azure Cognitive Search service
// ----------------------------------------------------

@description('Name of the Azure AI Search service')
param searchServiceName string = 'srch-${resourceToken}'

@description('Azure AI Search service SKU')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
])
param searchServiceSku string = 'standard'

@description('Search index name')
param searchIndexName string = 'index-name'

// Update Search service properties to support network security
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: searchServiceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned' // Add system-assigned managed identity for Search
  }
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    semanticSearch: 'free'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// ----------------------------------------------------
// Storage account for document storage
// ----------------------------------------------------

@description('Name of the storage account')
param storageAccountName string = 'st${replace(resourceToken, '-', '')}'

@description('Name of the blob container for documents')
param documentsContainerName string = 'documents'

@description('Name of the blob container for chunks')
param chunksContainerName string = 'chunks'

// Create Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// Create blob services
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
}

// Create container for documents
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: documentsContainerName
  properties: {
    publicAccess: 'None'
  }
}

// Create container for chunks
resource chunksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: chunksContainerName
  properties: {
    publicAccess: 'None'
  }
}

// ----------------------------------------------------
// Role assignments
// ----------------------------------------------------

// Assign 'Cognitive Services OpenAI User' role to App Service to call OpenAI
resource appServiceOpenAIUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appService.id, openAiAccount.id, 'Cognitive Services OpenAI User')
  scope: openAiAccount
  properties: {
    principalId: appService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') // Cognitive Services OpenAI User
  }
}

// Assign 'Search Index Data Reader' role to OpenAI to query search data
resource openAISearchDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, searchService.id, 'Search Index Data Reader')
  scope: searchService
  properties: {
    principalId: openAiAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f') // Search Index Data Reader
  }
}

// Assign 'Search Service Contributor' role to OpenAI for index schema access
resource openAISearchContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, searchService.id, 'Search Service Contributor')
  scope: searchService
  properties: {
    principalId: openAiAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') // Search Service Contributor
  }
}

// Assign 'Storage Blob Data Contributor' role to OpenAI for file access
resource openAIStorageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openAiAccount.id, storageAccount.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    principalId: openAiAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}

// Assign 'Cognitive Services OpenAI Contributor' role to Search to access OpenAI embeddings
resource searchOpenAIContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, openAiAccount.id, 'Cognitive Services OpenAI Contributor')
  scope: openAiAccount
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442') // Cognitive Services OpenAI Contributor
  }
}

// Assign 'Storage Blob Data Reader' role to Search for document and chunk access
resource searchStorageBlobDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, storageAccount.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
  }
}

// Assign 'Cognitive Services OpenAI Contributor' role to the user running the deployment
resource userOpenAIContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  name: guid(openAiAccount.id, userPrincipalId, 'Cognitive Services OpenAI Contributor')
  scope: openAiAccount
  properties: {
    principalId: userPrincipalId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442') // Cognitive Services OpenAI Contributor
  }
}

// ----------------------------------------------------
// Output values
// ----------------------------------------------------

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output APPSERVICE_NAME string = appService.name
output APPSERVICE_URI string = 'https://${appService.properties.defaultHostName}'
output OPENAI_ENDPOINT string = openAiAccount.properties.endpoint
output OPENAI_NAME string = openAiAccount.name
output SEARCH_SERVICE_NAME string = searchService.name
output SEARCH_SERVICE_ENDPOINT string = 'https://${searchService.name}.search.windows.net'
output STORAGE_ACCOUNT_NAME string = storageAccount.name

// ----------------------------------------------------
// App Service diagnostics settings
// ----------------------------------------------------

// Create Log Analytics workspace for App Service logs
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'law-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Configure diagnostic settings for the App Service
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: appService
  name: 'appServiceDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServiceAuditLogs'
        enabled: true
      }
      {
        category: 'AppServiceIPSecAuditLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}


