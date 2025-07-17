param(
    [Parameter(Mandatory=$true)]
    [string] $tenantId,

    [Parameter(Mandatory=$true)]
    [string] $subscriptionId,

    [Parameter(Mandatory=$true)]
    [string] $location,

    [Parameter(Mandatory=$true)]
    [string] $resourcePrefix,

    [Parameter(Mandatory=$true)]
    [string] $resourceSuffix,

    [Parameter(Mandatory=$false)]
    [string] $resourceGroupName = '',

    [Parameter(Mandatory=$false)]
    [string] $resourceGroupNamingConvention = 'rg',

    [Parameter(Mandatory=$false)]
    [string] $keyVaultNamingConvention = 'kv',

    [Parameter(Mandatory=$false)]
    [string] $storageAccountNamingConvention = 'dls',

    [Parameter(Mandatory=$false)]
    [string] $functionAppNamingConvention = 'func',

    [Parameter(Mandatory=$false)]
    [string] $dataFactoryNamingConvention = 'adf',

    [Parameter(Mandatory=$false)]
    [string] $sqlServerNamingConvention = 'sql',

    [Parameter(Mandatory=$false)]
    [string] $sqlDatabaseNamingConvention = 'sqldb',
    
    [Parameter(Mandatory=$false)]
    [string] $databricksNamingConvention = 'dbw'
)

Write-Host "Attempting to download and install post-deployment script artifacts..."

# Download and unzip the post-deployment artifact files from the repo
$zipUrl = "https://github.com/CloudFormations/CF.Marketplace/raw/refs/heads/develop_powershell/products/cf.cumulus/temp/postdeploy_artifacts.zip"
$tempPath = "deploymentFiles"

Invoke-WebRequest -Uri $zipUrl -OutFile "$tempPath.zip"
Expand-Archive -Path "$tempPath.zip" -DestinationPath $tempPath -Force

Write-Host "Post-deployment artifacts downloaded and extracted to $tempPath"

# Download the dotnet-install script

$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

$dotnetInstallDir = "$HOME/.dotnet"
Invoke-WebRequest -Uri "https://dot.net/v1/dotnet-install.sh" -OutFile "dotnet-install.sh"

bash ./dotnet-install.sh -InstallDir $dotnetInstallDir --architecture $architecture
$env:PATH = "$dotnetInstallDir;$dotnetInstallDir/tools;$env:PATH"
& "$dotnetInstallDir/dotnet" --version

# install other modules
Install-Module -Name SqlServer -Force -Scope CurrentUser
Install-Module -Name Az -Force -Scope CurrentUser
Install-Module -Name Az.DataFactory -Force -Scope CurrentUser
Install-Module -Name azure.datafactory.tools -Scope CurrentUser -Force
Install-Module -Name Az.Accounts -MinimumVersion 2.2.0 -Force -Scope CurrentUser

Invoke-WebRequest -Uri "https://aka.ms/InstallAzureCLIDeb" -OutFile "azurecli-install.sh"
bash ./azurecli-install.sh
az --version

Write-Host "Installed required modules."

# Login to the Azure Tenant
az login --tenant $tenantId


if ($resourceGroupName -eq '') { 
    $resourceGroupName = $resourcePrefix + $resourceGroupNamingConvention + $resourceSuffix
}
else {
    $resourceGroupName = $resourceGroupName
}

$keyVaultName = $resourcePrefix + $keyVaultNamingConvention + $resourceSuffix
$storageAccountName = $resourcePrefix + $storageAccountNamingConvention + $resourceSuffix
$functionAppName = $resourcePrefix + $functionAppNamingConvention + $resourceSuffix
$dataFactoryName = $resourcePrefix + $dataFactoryNamingConvention + $resourceSuffix
$sqlServerName = $resourcePrefix + $sqlServerNamingConvention + $resourceSuffix
$sqlDatabaseName = $resourcePrefix + $sqlDatabaseNamingConvention + $resourceSuffix
$databricksWorkspaceName = $resourcePrefix + $databricksNamingConvention + $resourceSuffix

$currentLocation = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
Write-Host "Current location: $currentLocation"

# Get Subscription Id from Name
$subscriptionDetails = az account subscription list | ConvertFrom-Json | Where-Object { $_.displayName -eq $subscriptionId }
$subscriptionIdValue = $subscriptionDetails.subscriptionId

$keyVaultId = az keyvault list --subscription $subscriptionIdValue --query "[?name=='$keyVaultName'].id" --output tsv
$keyVaultUri = "https://${keyVaultName}.vault.azure.net/"

$databricksWorkspaceURL = az databricks workspace show --name $databricksWorkspaceName --resource-group $resourceGroupName --subscription $subscriptionIdValue --query "workspaceUrl" --output tsv

# Grant User Key Vault Secret Administrator RBAC to save Function App Key to KV
$userDetails = az ad signed-in-user show | ConvertFrom-Json
$userId = $userDetails.id
az role assignment create --role "Key Vault Secrets Officer" --assignee $userId --scope "/subscriptions/$subscriptionIdValue/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName"

# Grant Databricks Key Vault Secrets User RBAC to read secrets from KV
# Get Databricks Object Id
$databricksDetails = az ad sp list --query "[?displayName=='AzureDatabricks']" | ConvertFrom-Json

az role assignment create --assignee-object-id $databricksDetails.id --role "Key Vault Secrets User" --scope "/subscriptions/$subscriptionIdValue/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$keyVaultName"


Write-Host "Attempting to deploy Functions to the function app: $functionAppName"
# Deploy the C# Functions to the Function App

# This command cleans the build output of the specified project using the Release configuration.
# Generates full paths in the output, and suppresses the summary in the console logger
$functionAppPath = "deploymentFiles\postdeploy_artifacts\azure.functionapp"
& "$dotnetInstallDir/dotnet" clean $functionAppPath --configuration Release /property:GenerateFullPaths=true /consoleloggerparameters:NoSummary

# Package the function app including the functions into a folder for deployment
$publishPath = $currentLocation + '\publishFunctions'
& "$dotnetInstallDir/dotnet" publish $functionAppPath --configuration Release --output $publishPath

# Compressing the publish folder into a zip file
$sourcePath = $publishPath + '/*'
Compress-Archive -Path $sourcePath -DestinationPath ./funcapp.zip -Update

# Deploying the zip to the functionapp
az functionapp deployment source config-zip --resource-group $resourceGroupName --name $functionAppName --src ./funcapp.zip

Write-Host "Attempting to add the Function App Key to Azure Key Vault secrets."
# Add Function App Key to Azure Key Vault secrets with the name cumulusfunctionsKey
$functionAppKeys = az functionapp keys list -g $resourceGroupName -n $functionAppName | ConvertFrom-Json 
$functionAppMasterKey = $functionAppKeys.masterKey
az keyvault secret set --vault-name $keyVaultName --name "cumulusfunctionsKey" --value $functionAppMasterKey

# Set environment variables for Data Factory LS deployments:
# Set environment variables up for other PS script executions
$Env:SQLSERVER = $sqlServerName 
$Env:SQLDATABASE = $sqlDatabaseName 
$Env:DATAFACTORY = $dataFactoryName 
$Env:FUNCTIONAPP = $functionAppName 
$Env:KEYVAULT = $keyVaultName 

Write-Host "Functions and function app key deployed successfully."
Write-Host "Attempting to deploy Data Factory objects to Data Factory: $dataFactoryName"
# Deploy Data Factory objects to Data Factory


# Get Deployment Objects and Params files
$scriptPath = "deploymentFiles\postdeploy_artifacts\azure.datafactory"

$options = New-AdfPublishOption
$options.CreateNewInstance = $false # New ADF workspace deployment not required.
$options.Excludes.Add("trigger.*","")
$options.Excludes.Add("factory.*","")


Publish-AdfV2FromJson -RootFolder "$scriptPath" -ResourceGroupName "$resourceGroupName" -DataFactoryName "$dataFactoryName" -Location "$location" -Option $options -Stage "install"

Write-Host "Data Factory objects deployed successfully."
Write-Host "Attempting to deploy Databricks resources to Databricks Workspace: $databricksWorkspaceName"
# Deploy Databricks Resources
    # Includes: Create PAT
    # Includes: Create Secret Scope
    # Includes: Create Cluster with ADLS Secret configuration
    # Includes: Add notebooks to Workspace/Live folder path

$secretScopeName = "CumulusScope01"

# Get Databricks Access Token
$DATABRICKS_AAD_TOKEN = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv

# Configure databricks config profile
$databrickscfgPath = "$($env:USERPROFILE)\.databrickscfg"
Write-Output "[DEFAULT]" | Out-File $databrickscfgPath -Encoding ASCII
Write-Output "host = https://$($databricksWorkspaceURL)" | Out-File $databrickscfgPath -Encoding ASCII -Append
Write-Output "token = $($DATABRICKS_AAD_TOKEN)" | Out-File $databrickscfgPath -Encoding ASCII -Append

$json = @"
{
    "scope": "$secretScopeName",
    "scope_backend_type": "AZURE_KEYVAULT",
    "backend_azure_keyvault": {
        "resource_id": "$keyVaultId",
        "dns_name": "$keyVaultUri"
    }
}
"@

# Create Databricks Secret Scope
# TODO: Make command idempotent in event that the scope already exists
databricks secrets create-scope --json $json --profile DEFAULT

# Create Databricks Cluster
$sparkConfig = @"
{
    "spark.sql.ansi.enabled": "true",
    "fs.azure.account.key.$storageAccountName.dfs.core.windows.net": "{{secrets/$secretScopeName/$($storageAccountName)rawaccesskey}}"
}
"@

$clusterJSON = @"
{
    "cluster_name": "General Purpose Cluster",
    "spark_version": "15.4.x-scala2.12",
    "spark_conf": $sparkConfig,
    "azure_attributes": {
        "availability": "SPOT_WITH_FALLBACK_AZURE"
    },
    "node_type_id": "Standard_D4ds_v5",
    "autotermination_minutes": 20,
    "data_security_mode": "DATA_SECURITY_MODE_AUTO",
    "runtime_engine": "STANDARD",
    "kind": "CLASSIC_PREVIEW",
    "is_single_node": false,
    "autoscale": {
        "min_workers": 1,
        "max_workers": 4
    }
}
"@

databricks clusters create --json $clusterJSON --profile DEFAULT


# Programmatically find databricks folder path in Repo
$scriptPath = "deploymentFiles\postdeploy_artifacts\azure.databricks"
$revertPath = Get-Location

# Deploy Notebooks to Workspace 
$sourcePath = $scriptPath + '\python\notebooks'
Set-Location -Path $sourcePath
databricks bundle deploy --target DEFAULT
Set-Location -Path $revertPath

Write-Host "Databricks resources deployed successfully."
Write-Host "Attempting to deploy SQL Server Metadata objects to SQL Server: $sqlServerName"
# Deploy the SQL Server Metadata objects

# Upgrade script functionality: Add current IP address to Firewall
az sql server firewall-rule create -g $resourceGroupName -s $sqlServerName -n CumulusDeploymentIPRequirement --start-ip-address 51.194.125.40 --end-ip-address 51.194.125.40


# Includes: Publish DacPacs to the instance
# Includes: Create user for ADF, create role, grant role permissions, add user to role
# Get SQL User and Password from Key Vault to deploy DacPacs
$sqlValueSecret = $sqlServerName + '-adminpassword'
$sqlUsernameSecret = $sqlServerName + '-adminusername'

$sqlLogin = az keyvault secret show --name $sqlUsernameSecret --vault-name $keyVaultName --query "value"

$sqlPassword = az keyvault secret show --name $sqlValueSecret --vault-name $keyVaultName --query "value"

$sourceFolderPath = "deploymentFiles\postdeploy_artifacts"

# Publish the common schema DacPac
SqlPackage /Action:Publish /SourceFile:"$sourceFolderPath\metadata.common.dacpac" /TargetConnectionString:"Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=$sqlDatabaseName;Persist Security Info=False;User ID=$sqlLogin;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" /v:DatabricksWSName=$databricksWorkspaceName /v:DatabricksHost="https://$databricksWorkspaceURL" /v:DLSName=$storageAccountName  /v:Environment="Dev"  /v:KeyVaultName=$keyVaultName  /v:RGName=$resourceGroupName /v:SubscriptionID=$subscriptionIdValue 

# Publish the control schema DacPac
SqlPackage /Action:Publish /SourceFile:"$sourceFolderPath\metadata.control.dacpac" /TargetConnectionString:"Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=$sqlDatabaseName;Persist Security Info=False;User ID=$sqlLogin;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" /v:Environment="Dev"  /v:RGName=$resourceGroupName /v:SubscriptionID=$subscriptionIdValue /v:ADFName=$dataFactoryName /v:TenantID=$tenantId

# Publish the ingest schema DacPac
SqlPackage /Action:Publish /SourceFile:"$sourceFolderPath\metadata.ingest.dacpac" /TargetConnectionString:"Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=$sqlDatabaseName;Persist Security Info=False;User ID=$sqlLogin;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" 

# Publish the transform schema DacPac
SqlPackage /Action:Publish /SourceFile:"$sourceFolderPath\metadata.transform.dacpac" /TargetConnectionString:"Server=tcp:$sqlServerName.database.windows.net,1433;Initial Catalog=$sqlDatabaseName;Persist Security Info=False;User ID=$sqlLogin;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" 


# Set Entra AD admin to myself for this:
$userDetails = az ad signed-in-user show --query userPrincipalName --output tsv
$userId = az ad signed-in-user show --query id --output tsv
az sql server ad-admin create --resource-group $resourceGroupName --server $sqlServerName --display-name $userDetails --object-id $userId

Write-Host "SQL server metadata objects deployed successfully."
Write-Host "Attempting to add ADF Permissions to SQL Server: $sqlServerName"
# Create permissions for ADF on the SQL Instance, including a user, role and assigment of user to the role
Import-Module -Name SqlServer -Verbose

$accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token

$sqlServerNameFull = "$sqlServerName.database.windows.net"

$query = @"
-- Cumulus Additional Database Data Source Pre-requisites
IF NOT EXISTS (SELECT * FROM sys.sysusers WHERE name = '$dataFactoryName')
BEGIN
	CREATE USER [$dataFactoryName] FROM EXTERNAL PROVIDER;
	PRINT 'Created ADF user'
END

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE type = 'R' AND name = 'db_cumulususer')
BEGIN
	CREATE ROLE [db_cumulususer];
	PRINT 'Created db_cumulususer role'
END

GRANT 
	EXECUTE, 
	SELECT,
	CONTROL,
	ALTER
ON SCHEMA::[control] TO [db_cumulususer];
GO

GRANT 
	EXECUTE, 
	SELECT,
	CONTROL,
	ALTER
ON SCHEMA::[ingest] TO [db_cumulususer];
GO

GRANT 
	EXECUTE, 
	SELECT,
	CONTROL,
	ALTER
ON SCHEMA::[transform] TO [db_cumulususer];
GO

ALTER ROLE [db_cumulususer] 
ADD MEMBER [$dataFactoryName];
"@


Invoke-Sqlcmd -ServerInstance $sqlServerNameFull -Database $sqlDatabaseName -AccessToken $accessToken -Query $query

$sqlPassword = $null

# Upgrade script functionality: Delete current IP address from Firewall
az sql server firewall-rule delete  -g $resourceGroupName -s $sqlServerName -n CumulusDeploymentIPRequirement

Write-Host "ADF Permissions added to SQL Server successfully."
Write-Host "Post Deployment complete."
