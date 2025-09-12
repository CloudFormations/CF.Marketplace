//  Main infrastructure deployment template for a CF.Cumulus data platform
//  Deploys core services including:
//  - Key Vault, Storage, Data Factory, Databricks, Function Apps, SQL Server
//  - Configures role assignments and dependencies between services

//targetScope = 'resourceGroup'

//Parameters for environment configuration
// * These parameters control resource naming and deployment options
// * Recommended for consistent resource naming across environments

//Naming convention parameters
//**************************************************************************************************************
@description('The naming prefix for all resources to be deployed.')
param orgName string = 'nice'

@description('The optional middle part naming for all resources to be deployment. Suggested as the business unit, project or domain.')
param domainName string = 'dev'

@description('The environment name abbreviation used for the deployment.')
param envName string = 'dev'

@description('The Azure region where all resources will be deployed.')
param location string = 'centralus'

@description('Optional naming abbreviation for the Azure Data Lake Storage account.')
param datalakeName string = 'dls'

@description('Optional naming abbreviation for the Azure Storage account used to support the Azure Functions App.')
param functionStorageName string = 'st'

@description('The numeric identifier for all resources as a naming suffix, used to differentiate between instances of resources.')
param uniqueIdentifier string = '01'

//Parameters to support resource configuration
//**************************************************************************************************************
@description('The product SKU for the Azure Databricks workspace.')
@allowed(['Premium','Standard'])
param databricksSKU string = 'Standard'

@description('The product SKU for the App Service Plan used by the Azure Function App.')
@allowed(['premium','consumption'])
param aspSKU string = 'consumption'

@description('Deploy the SQL DACPAC required for the metadata database objects.')
param deploySQLDacpac bool = true

@description('An external IP address that is allowed access to the Azure SQL Database, as part of the logical SQL instance Firewall Rules.')
param myIPAddress string = '182.64.82.18'

@description('Allow Azure services to access the Azure SQL Database, as part of the logical SQL instance Firewall Rules. Required for Azure Data Factory MI authentication.')
param allowAzureServices bool = true

@description('A timestamp format used for the deployment execution naming only. Used to differentiate between instances of resources deployed.')
param deploymentTimestamp string = utcNow('yy-MM-dd-HHmm')

//Parameters for optional resource deployments considering new vs existing instances
//**************************************************************************************************************
@description('Optionally deploy Azure Data Factory, if it already exists.')
param deployADF bool = true

@description('Optionally deploy a separate Azure Data Factory instance to house Worker and Bootstrap pipelines separately.')
param deployWorkers bool = false

@description('Optionally deploy an Azure SQL Database to house all metadata, if it already exists.')
param deploySQL bool = true

@description('Optionally deploy an Azure Function App, if it already exists.')
param deployFunction bool = true

@description('Optionally deploy an Azure Databricks workspace, if it already exists.')
param deployADBWorkspace bool = true

@description('Optionally setup role assignments as part of the deployment.')
param setRoleAssignments bool = false

@description('Optionally deploy a custom VNet for the Azure Databricks workspace.')
param deployNetworking bool = false

@description('Optionally deploy a Virtual Machine to house self-hosted Integration Runtime (IR) for Azure Data Factory.')
param deployVM bool = false

@description('Optionally configure GitHub repository for Azure Data Factory.')
param configureGitHub bool = false


//End of parameters - no need to change anything below
//**************************************************************************************************************
//**************************************************************************************************************
//**************************************************************************************************************

// Mapping of Azure regions to short codes for naming conventions
var locationShortCodes = {
  uksouth: 'uks'
  ukwest: 'ukw'
  eastus: 'eus'
  westus: 'wus'
  westus2: 'wus2'
  centralus: 'cus'
  northcentralus: 'ncus'
  southcentralus: 'scus'
  eastus2: 'eus2'
  westeurope: 'weu'
  northeurope: 'neu'
  francecentral: 'frc'
  germanywestcentral: 'gwc'
  switzerlandnorth: 'swn'
  norwayeast: 'noe'
  brazilsouth: 'brs'
  canadacentral: 'cac'
  canadaeast: 'cae'
}

var locationShortCode = locationShortCodes[location]

// Resource naming convention variables
var namePrefix = '${orgName}${domainName}${envName}'
var nameSuffix = '${locationShortCode}${uniqueIdentifier}'
var DataBricksWorkspaceName = '${namePrefix}dbw${nameSuffix}'
var managedResourceGroupName = '${namePrefix}rgm${nameSuffix}'
var PostDeployDownloadArtifactsURL = 'https://github.com/CloudFormations/CF.Marketplace/raw/refs/heads/develop_powershell/products/cf.cumulus/temp/postdeploy_artifacts.zip'
var SecretScopeName = 'CumulusScope01'
var DataBricksClusterName = 'GeneralPurposeCluster'
var ExistingAzureDataBricksAppID = '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d'

// Monitoring Resources
module logAnalyticsDeploy './modules/loganalytics.template.bicep' = {
  name: 'log-analytics${deploymentTimestamp}'
  params: {
    envName: envName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
}

module appInsightsDeploy './modules/applicationinsights.template.bicep' = {
  name: 'app-insights${deploymentTimestamp}'
  params: {
    envName: envName
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
  dependsOn: [
    logAnalyticsDeploy
  ]
}

// Base resources
module keyVaultDeploy './modules/keyvault.template.bicep' = {
  name: 'keyvault${deploymentTimestamp}'
  params: {
    namePrefix: namePrefix
    nameSuffix: nameSuffix
  }
  dependsOn: [
    logAnalyticsDeploy
  ]
}

// Datafactory Resources
module dataFactoryDeployOrchestrator './modules/datafactory.template.bicep' = if (deployADF) {
  name: 'datafactory-orchestrator${deploymentTimestamp}'
  params: {
    nameFactory: deployWorkers ? 'factory' : 'adf' // if workers adf is being setup we call this one factory, otherwise we call it adf
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    configureGitHub: configureGitHub
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}

// // Additional Data Factory Resource deployment if you require mulitple instances 
module dataFactoryDeployWorkers './modules/datafactory.template.bicep' = if (deployADF && deployWorkers) {
  name: 'datafactory-workers${deploymentTimestamp}'
  params: {
    nameFactory: 'workers'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    configureGitHub: configureGitHub
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}

// Deploy ADLS for Data Lake
module storageAccountDeploy './modules/storage.template.bicep' = {
  name: 'storageaccount${deploymentTimestamp}'
  params: {
    isHnsEnabled: true
    isSftpEnabled: false
    accessTier: 'Hot'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
    storageKind: 'StorageV2'
    containers: {
      bronze: {
        name: 'raw'
      }
      silver: {
        name: 'cleansed'
      }
      gold: {
        name: 'curated'
      }
    }
    envName: envName
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}

// Deploy Function App
// Deploy Function App Storage Account
module functionStorageAccountDeploy './modules/storage.template.bicep' = if (deployFunction) {
  name: 'functionStorage${deploymentTimestamp}'
  params: {
    containers: {}
    envName: envName
    isHnsEnabled: false
    isSftpEnabled: false
    namePrefix: namePrefix
    nameStorage: functionStorageName
    nameSuffix: nameSuffix
    storageKind: 'StorageV2'
  }
  dependsOn: [
    keyVaultDeploy
    appInsightsDeploy
    logAnalyticsDeploy
  ]
}

// Deploy Function App + ASP
module functionAppDeploy './modules/functionapp.template.bicep' = if (deployFunction) {
  name: 'functionApp${deploymentTimestamp}'
  params: {
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: functionStorageName
    aspSKU: aspSKU
  }
  dependsOn: [
    keyVaultDeploy
    appInsightsDeploy
    logAnalyticsDeploy
    functionStorageAccountDeploy
  ]
}

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'functionZipDeployIdentity'
  location: location
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userAssignedIdentity.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userAssignedIdentity.id, 'KeyVaultSecretsOfficer')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource adfRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, userAssignedIdentity.id, 'Data Factory Contributor')
  properties: {
    principalId: userAssignedIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '673868aa-7521-48a0-acc6-0f60742d39f5') // Data Factory Contributor
    principalType: 'ServicePrincipal'
  }
}

// resource AddReadPermissionToManagedID 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
//   name: 'AddReadPermissionToManagedID'
//   location: location
//   kind: 'AzurePowerShell'
//   properties: {
//     azPowerShellVersion: '14.2'
//     arguments: '-tenantId ${userAssignedIdentity.properties.tenantId} -MSIName ${userAssignedIdentity.name}'
//     scriptContent: loadTextContent('./scripts/AddReadPermissionToManagedID.ps1')
//     cleanupPreference: 'OnSuccess'
//     retentionInterval: 'PT1H'
//   }
//   // dependsOn: [
//   //   databricksWorkspaceDeploy
//   // ]
// }

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'FunctionAppZipDeploy'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0'
    arguments: '-ResourceGroupName ${resourceGroup().name} -FunctionAppName ${functionAppDeploy.outputs.functionAppName}'
    scriptContent: loadTextContent('./scripts/FunctionAppDeployment.ps1')
    cleanupPreference: 'OnExpiration'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    functionAppDeploy
  ]
}

resource script 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'StoreFunctionAppKeyToKV'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.56.0'
    arguments: '-ResourceGroupName ${resourceGroup().name} -FunctionAppName ${functionAppDeploy.outputs.functionAppName} -KeyVaultName ${keyVaultDeploy.outputs.name}'
    environmentVariables: [
      { name: 'FUNCTION_APP_NAME', value: functionAppDeploy.outputs.functionAppName}
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'KEYVAULT_NAME', value: keyVaultDeploy.outputs.name }
    ]
    scriptContent: '''
      echo "Fetching function app master key..."
      MASTER_KEY=$(az functionapp keys list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query masterKey -o tsv)

      echo "Storing master key in Key Vault..."
      az keyvault secret set --vault-name $KEYVAULT_NAME --name "cumulusfunctionsKey" --value "$MASTER_KEY"
    '''
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    keyVaultDeploy
    functionAppDeploy
    kvSecretOfficer
    deploymentScript
  ]
}

// resource deployAdfArtifacts 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
//   name: 'deployAdfObjects'
//   location: location
//   kind: 'AzurePowerShell'
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${userAssignedIdentity.id}': {}
//     }
//   }
//   properties: {
//     azPowerShellVersion: '14.2'
//     arguments: '-ResourceGroupName ${resourceGroup().name} -DataFactoryName ${dataFactoryDeployOrchestrator.outputs.name}'
//     scriptContent: loadTextContent('./scripts/DataFactoryDeployment.ps1')
//     retentionInterval: 'PT1H'
//     timeout: 'PT1H'
//     cleanupPreference: 'OnSuccess'
//   }
//   dependsOn: [
//     dataFactoryDeployOrchestrator
//     keyVaultDeploy
//     adfRoleAssignment // if you store paths/keys in Key Vault
//   ]
// }

// Deploy SQL Server with a basic blank database
module sqlServerDeploy './modules/sqlserver.template.bicep' = if (deploySQL) {
  name: 'sql-server${deploymentTimestamp}'
  params: {
    myIPAddress: myIPAddress
    allowAzureServices: allowAzureServices
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    userAssignedIdentity: userAssignedIdentity.id
  }
  dependsOn: [
    keyVaultDeploy
    logAnalyticsDeploy
  ]
}

resource databricksWorkspaceDeploy 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'CreateDataBricksWorkspace'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '14.2'
    arguments: '-ResourceGroupName ${resourceGroup().name} -DataBricksWorkspaceName ${DataBricksWorkspaceName} -Location ${location} -ManagedResourceGroupName ${managedResourceGroupName} -DatabricksSKU ${databricksSKU}'
    scriptContent: loadTextContent('./scripts/CreateDataBricksWorkspace.ps1')
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'PT1H'
  }
  // dependsOn: [
  //   databricksWorkspaceDeploy
  // ]
}

// resource databricksWorkspaceConfigure 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
//   name: 'databricksWorkspaceConfigure'
//   location: location
//   kind: 'AzurePowerShell'
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${userAssignedIdentity.id}': {}
//     }
//   }
//   properties: {
//     azPowerShellVersion: '11.0'
//     scriptContent: loadTextContent('./scripts/ConfigureDataBricksWorkspace.ps1')
//     arguments: '-ResourceGroupName ${resourceGroup().name} -DataBricksServiceName ${databricksWorkspaceDeploy.properties.outputs.workspaceName} -SecretScopeName ${secretScopeName} -KeyVaultID ${keyVaultDeploy.outputs.keyVaultId} -KeyVaultURI ${keyVaultDeploy.outputs.keyVaultUri} -StorageAccountName ${storageAccountDeploy.outputs.name} -DownloadArtifactsURL ${PostDeployDownloadArtifactsURL}'
//     retentionInterval: 'P1D'
//     timeout: 'PT1H'
//     cleanupPreference: 'OnSuccess'
//   }
//   dependsOn: [
//     databricksWorkspaceDeploy
//     keyVaultDeploy
//   ]
// }

// // Role Assignments:
// // Data Factory Role Assignments
module dataFactoryOrchestratorRoleAssignmentsDeploy './modules/roleassignments/datafactory.template.bicep' = if (deployADF && setRoleAssignments) {
  name: 'adf-orchestration-roleassignments${deploymentTimestamp}'
  params: {
    nameFactory: deployWorkers ? 'factory' : 'adf' // if workers adf is being setup we call this one factory, otherwise we call it adf
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
    statusADB: deployADBWorkspace
    statusFunction: deployFunction
  }
  dependsOn: [
    keyVaultDeploy
    storageAccountDeploy
    dataFactoryDeployOrchestrator
    deploySQL ? sqlServerDeploy : null
    deployFunction ? functionAppDeploy : null
    deployADBWorkspace ? databricksWorkspaceDeploy : null
  ]
}

// // Data Factory Role Assignments
module dataFactoryWorkersRoleAssignmentsDeploy './modules/roleassignments/datafactory.template.bicep' = if (deployWorkers && setRoleAssignments) {
  name: 'adf-workers-roleassignments${deploymentTimestamp}'
  params: {
    nameFactory: 'workers'
    namePrefix: namePrefix
    nameSuffix: nameSuffix
    nameStorage: datalakeName
    statusADB: deployADBWorkspace
    statusFunction: deployFunction
  }
  dependsOn: [
    keyVaultDeploy
    storageAccountDeploy
    dataFactoryDeployWorkers
    deploySQL ? sqlServerDeploy : null
    deployFunction ? functionAppDeploy : null
    deployADBWorkspace ? databricksWorkspaceDeploy : null
  ]
}

// // // Databricks Role Assignments
module databricksRoleAssignmentsDeploy './modules/roleassignments/databricks.template.bicep' = if (deployADBWorkspace && setRoleAssignments) {
  name: 'databricks-roleassignments${deploymentTimestamp}'
  params: {
    adbWorkspaceName: databricksWorkspaceDeploy.properties.outputs.workspaceName
    nameStorage: datalakeName
    //keyVaultName: keyVaultDeploy.outputs.name
    databricksID: databricksWorkspaceDeploy.properties.outputs.workspaceId
  }
  dependsOn: [
    keyVaultDeploy
    storageAccountDeploy
    databricksWorkspaceDeploy
    dataFactoryDeployOrchestrator
  ]
}

// resource deploySqlMetadata 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
//   name: 'deploy-sqlmetadata'
//   location: location
//   kind: 'AzurePowerShell'
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${userAssignedIdentity.id}': {}
//     }
//   }
//   properties: {
//     azPowerShellVersion: '11.0' // latest stable Az module
//     timeout: 'PT1H'
//     retentionInterval: 'P1D'
//     scriptContent: loadTextContent('./scripts/DeploySQLDacpac.ps1')
//     //arguments: ''
//     environmentVariables: [
//       { name: 'ResourceGroupName',        value: resourceGroup().name }
//       { name: 'SqlServerName',            value: sqlServerDeploy.outputs.sqlServerName }
//       { name: 'SqlDatabaseName',          value: sqlServerDeploy.outputs.databaseName }
//       { name: 'KeyVaultName',             value: keyVaultDeploy.outputs.name }
//       { name: 'StorageAccountName',       value: storageAccountDeploy.outputs.name }
//       { name: 'DataBricksServiceName',    value: databricksWorkspaceDeploy.properties.outputs.workspaceName }
//       { name: 'DataFactoryName',          value: dataFactoryDeployOrchestrator.outputs.name }
//       { name: 'PostDeployDownloadArtifactsURL', value: PostDeployDownloadArtifactsURL }
//     ]
//   }
// }

resource deploySqlMetadata 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'PostDeploymentActions'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '11.0' // latest stable Az module
    timeout: 'PT1H'
    retentionInterval: 'P1D'
    scriptContent: loadTextContent('./scripts/PostDeploymentConfigurations.ps1')
    //arguments: ''
    environmentVariables: [
      { name: 'ResourceGroupName',              value: resourceGroup().name }
      { name: 'SqlServerName',                  value: sqlServerDeploy.outputs.sqlServerName }
      { name: 'SqlDatabaseName',                value: sqlServerDeploy.outputs.databaseName }
      { name: 'KeyVaultName',                   value: keyVaultDeploy.outputs.name }
      { name: 'KeyVaultID',                     value: keyVaultDeploy.outputs.keyVaultId }
      { name: 'KeyVaultURI',                    value: keyVaultDeploy.outputs.keyVaultUri }
      { name: 'StorageAccountName',             value: storageAccountDeploy.outputs.name }
      { name: 'DataBricksServiceName',          value: databricksWorkspaceDeploy.properties.outputs.workspaceName }
      { name: 'SecretScopeName',                value: SecretScopeName }
      { name: 'DataBricksClusterName',          value: DataBricksClusterName }
      { name: 'ExistingAzureDataBricksAppID',   value: ExistingAzureDataBricksAppID }
      { name: 'DataFactoryName',                value: dataFactoryDeployOrchestrator.outputs.name }
      { name: 'PostDeployDownloadArtifactsURL', value: PostDeployDownloadArtifactsURL }
      { name: 'CurrentUserManagedIdentityID',   value: userAssignedIdentity.properties.principalId }
      { name: 'CurrentUserManagedIdentityName', value: userAssignedIdentity.name }
    ]
  }
}

// resource AddDataFactoryUserToDB 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
//   name: 'AddDataFactoryUserToDB'
//   location: location
//   kind: 'AzurePowerShell'
//   properties: {
//     azPowerShellVersion: '11.0'
//     arguments: '-ResourceGroupName ${resourceGroup().name} -SqlServerName ${sqlServerDeploy.outputs.sqlServerName} -SqlDatabaseName ${sqlServerDeploy.outputs.databaseName} -DataFactoryName ${dataFactoryDeployOrchestrator.outputs.name} -keyVaultName ${keyVaultDeploy.outputs.name}'
//     scriptContent: loadTextContent('./scripts/AddDataDactoryUserToDB.ps1')
//     cleanupPreference: 'OnExpiration'
//     retentionInterval: 'PT1H'
//   }
//   dependsOn: [
//     sqlServerDeploy
//   ]
// }

// OUTPUTS
output logAnalyticsDeploy string = logAnalyticsDeploy.outputs.resourceId
output keyVaultName string = keyVaultDeploy.outputs.name
output keyVaultUri string = keyVaultDeploy.outputs.keyVaultUri
output keyVaultId string = keyVaultDeploy.outputs.keyVaultId
output storageAccountName string = storageAccountDeploy.outputs.name
output functionAppName string = functionAppDeploy.outputs.functionAppName
output deploymentScriptOutput string = deploymentScript.properties.arguments
output sqlServerName string = sqlServerDeploy.outputs.sqlServerName
output sqlDatabaseName string = sqlServerDeploy.outputs.databaseName

// output databricksWorkspaceURL string = databricksWorkspaceDeploy.properties.outputs.workspaceUrl
// output databricksWorkspaceId string = databricksWorkspaceDeploy.properties.outputs.workspaceId
// output databricksWorkspaceName string = databricksWorkspaceDeploy.properties.outputs.workspaceName
// output dataFactoryName string = dataFactoryDeployOrchestrator.outputs.name
// output dataFactoryID string = dataFactoryDeployOrchestrator.outputs.resourceId
