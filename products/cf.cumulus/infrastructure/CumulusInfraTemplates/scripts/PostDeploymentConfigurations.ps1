<#
.SYNOPSIS
    Deploys SQL Server metadata objects (DACPACs) and configures ADF access.

.DESCRIPTION
    - Adds temporary firewall rule
    - Retrieves SQL admin credentials from Key Vault
    - Publishes DACPAC files to SQL DB
    - Sets Azure AD Admin for SQL Server
    - Creates ADF user/role and grants schema permissions
    - Cleans up firewall rules

.PARAMETER ResourceGroupName
    Azure Resource Group containing SQL Server

.PARAMETER SqlServerName
    SQL Server name

.PARAMETER SqlDatabaseName
    SQL Database name

.PARAMETER KeyVaultName
    Key Vault holding SQL credentials

.PARAMETER KeyVaultID
    Azure Key Vault ID

.PARAMETER KeyVaultURI
    Azure Key Vault URI

.PARAMETER StorageAccountName
    Azure Storage account name

.PARAMETER DataBricksServiceName
    Azure Data Bricks Service Name

.PARAMETER SecretScopeName
    Azure Data Bricks Service Secret Scope

.PARAMETER DataBricksClusterName
    Azure Data Bricks Cluster Name

.PARAMETER ExistingAzureDataBricksAppID
    Application ID of PreExist Data Bricks Service Principle 

.PARAMETER DataFactoryName
    Azure Data Factory name

.PARAMETER TenantId
    Azure Tenant Id

.PARAMETER PostDeployDownloadArtifactsURL
    Download URL where Post Deployment Artifacs and Config file are stored

.PARAMETER CurrentUserManagedIdentityID
    Current User Principle ID (Managed Identity)

.PARAMETER CurrentUserManagedIdentityName
    Current User Principle Name (Managed Identity)

#>

$ResourceGroupName = $env:ResourceGroupName
$SqlServerName = $env:SqlServerName
$SqlDatabaseName = $env:SqlDatabaseName
$KeyVaultName = $env:KeyVaultName
$KeyVaultID = $env:KeyVaultID
$KeyVaultURI = $env:KeyVaultURI
$StorageAccountName = $env:StorageAccountName
$DataBricksServiceName = $env:DataBricksServiceName
$SecretScopeName = $env:SecretScopeName
$DataBricksClusterName = $env:DataBricksClusterName
$ExistingAzureDataBricksAppID = $env:ExistingAzureDataBricksAppID
$DataFactoryName = $env:DataFactoryName
$PostDeployDownloadArtifactsURL = $env:PostDeployDownloadArtifactsURL
$CurrentUserManagedIdentityID = $env:CurrentUserManagedIdentityID
$CurrentUserManagedIdentityName = $env:CurrentUserManagedIdentityName

Write-Host "Resource Group Name: $ResourceGroupName"
Write-Host "Sql Server Name: $SqlServerName"
Write-Host "Sql Database Name: $SqlDatabaseName"
Write-Host "Key Vault Name: $KeyVaultName"
Write-Host "key Vault ID: $KeyVaultID"
Write-Host "key Vault URI: $KeyVaultURI"
Write-Host "Storage Account Name: $StorageAccountName"
Write-Host "Data Bricks Service Name: $DataBricksServiceName"
Write-Host "Secret Scope Name: $SecretScopeName"
Write-Host "Storage Account Name: $DataBricksClusterName"
Write-Host "Existing Azure Data Bricks App ID: $ExistingAzureDataBricksAppID"
Write-Host "Data Factory Name: $DataFactoryName"
Write-Host "Post Deployment Download Artifacts URL: $PostDeployDownloadArtifactsURL"
Write-Host "CurrentUserManagedIdentityID = $CurrentUserManagedIdentityID"
Write-Host "CurrentUserManagedIdentityName = $CurrentUserManagedIdentityName"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Level) {
        "ERROR"   { Write-Host "[$timestamp][ERROR]   $Message" -ForegroundColor Red }
        "SUCCESS" { Write-Host "[$timestamp][SUCCESS] $Message" -ForegroundColor Green }
        "WARN"    { Write-Host "[$timestamp][WARN]    $Message" -ForegroundColor Yellow }
        default   { Write-Host "[$timestamp][INFO]    $Message" -ForegroundColor Cyan }
    }
}

Write-Log "STARTED === Setting up Environment with Installing prerequisites and Downloding required configurations files ==="
############### Install the Azure CLI module. ###############
Write-Host "Instaling Azure CLI..."
Invoke-WebRequest -Uri "https://aka.ms/InstallAzureCLIDeb" -OutFile "azurecli-install.sh"
bash ./azurecli-install.sh
az --version

############### Install the Azure Data Bricks Tools module. ###############
Write-Host "Instaling Azure Data Bricks Tools module..."
bash -c "apt-get update && apt-get install -y unzip"
# Install Databricks CLI
bash -c "curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"
# Add Databricks CLI to PATH
$env:PATH += ":$HOME/.databricks/bin"
# Verify installation
databricks --version

############### Install the Azure Data Factory Tools module. ###############
Write-Host "Instaling Azure Data Factory Tools module..."
Write-Host "Install-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force -AllowClobber -Scope CurrentUser"
Install-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force -AllowClobber -Scope CurrentUser
Write-Host "Import the module to make its cmdlets available."
Import-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force
Get-Module -Name Az.Accounts -ListAvailable

############### Install the Azure SQL Tools module. ###############
Write-Host "Instaling Azure SQL Tools module..."
$installPath = "sqlpackage"
# download zip
Invoke-WebRequest -Uri "https://aka.ms/sqlpackage-linux" -OutFile "$installPath.zip" -UseBasicParsing
Expand-Archive -Path "$installPath.zip" -DestinationPath $installPath -Force -ErrorAction Stop
Install-Module -Name SqlServer -Force -Scope CurrentUser

# Download artifacts
$ArtifactFilesDestinationPath = "deploymentFiles"
Write-Output "Downloading artifacts from $PostDeployDownloadArtifactsURL ..."
Invoke-WebRequest -Uri $PostDeployDownloadArtifactsURL -OutFile "$ArtifactFilesDestinationPath.zip" -ErrorAction Stop
Write-Output "Download completed."

# Extract zip
Write-Output "Extracting artifacts to $ArtifactFilesDestinationPath ..."
Expand-Archive -Path "$ArtifactFilesDestinationPath.zip" -DestinationPath $ArtifactFilesDestinationPath -Force -ErrorAction Stop
Write-Output "Extraction completed."

Write-Log "COMPLETED === Setting up Environment with Installing prerequisites and Downloding required configurations files ==="

#####################################################################################
### Data Factory Deployment Started #################################################
#####################################################################################
function Deploy-DataFactory {
    Write-Log "STARTED: Azure Data Factory Deployment..."

    # Get Deployment Objects and Config files
    $DeployDataFactoryConfigFilePath = "deploymentFiles\postdeploy_artifacts\azure.datafactory"

    #$options = New-AdfPublishOption
    #$options.CreateNewInstance = $false
    #$options.Excludes.Add("trigger.*")
    #$options.Excludes.Add("factory.*")

    Publish-AdfV2FromJson -RootFolder "$DeployDataFactoryConfigFilePath" -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Location "centralus" -Stage "install"

    Write-Log "COMPLETED: Azure Data Factory Deployment..."
}

#####################################################################################
### Data Bricks Workspace Deployment Started ########################################
#####################################################################################
function Deploy-DataBricksWorkspace {
    Write-Log "STARTED: Data Bricks Workspace Deployment..."

    Write-Host "Fetching Data Bricks Access Toekn..."
    $DataBricksADDToken = az account get-access-token --resource $ExistingAzureDataBricksAppID --query accessToken --output tsv

    if (-not $DataBricksADDToken) {
        throw "Failed to acquire AAD token for Databricks."
    }

    Write-Host "Fetching databricks Workspace Name and Workspace URL"
    $DataBricksWorkspaceName = (az databricks workspace show --name $DataBricksServiceName --resource-group $ResourceGroupName --query "workspaceUrl" -o tsv)
    $DataBricksWorkspaceURL = "https://$DataBricksWorkspaceName"
    Write-Host "DataBricks Workspace Name: $DataBricksWorkspaceName"
    Write-Host "DataBricks Workspace URL: $DataBricksWorkspaceURL"

    # Set environment variables for Databricks CLI
    $env:DATABRICKS_HOST = $DataBricksWorkspaceURL
    $env:DATABRICKS_AAD_TOKEN = $DataBricksADDToken

    Write-Host "Configuring databricks config profile"
    $databrickscfgPath = "$($env:USERPROFILE)\.databrickscfg"
    Write-Host "databrickscfgPath = $databrickscfgPath"
    Write-Output "[DEFAULT]" | Out-File $databrickscfgPath -Encoding ASCII
    Write-Output "host = https://$($DataBricksWorkspaceName)" | Out-File $databrickscfgPath -Encoding ASCII -Append
    Write-Output "token = $($DataBricksADDToken)" | Out-File $databrickscfgPath -Encoding ASCII -Append

    # Prepare JSON
    Write-Host "loading Json Payload to create DataBricks Secret Scope"
$json = @"
{
    "scope": "$SecretScopeName",
    "initial_manage_principal": "users",
    "scope_backend_type": "AZURE_KEYVAULT",
    "backend_azure_keyvault": {
        "resource_id": "$KeyVaultID",
        "dns_name": "$KeyVaultURI"
    }
}
"@

    try {
        Write-Output "Checking if secret scope [$SecretScopeName] already exists..."
        # Get existing secret scopes
        $scopes = databricks secrets list-scopes | Select-Object -Skip 1
        # Check if scope exists
        $scopeExists = $scopes -match ("^" + [Regex]::Escape($SecretScopeName) + "\b")
        if ($scopeExists) {
            Write-Output "Secret scope [$SecretScopeName] already exists. Skipping creation."
        }
        else {
            Write-Output "Creating secret scope [$SecretScopeName] linked to Key Vault [$KeyVaultURI]..."
            databricks secrets create-scope --json $json
            Write-Output "Secret scope [$SecretScopeName] created successfully."
        }
        Write-Output "Listing all available secret scopes..."
        databricks secrets list-scopes
    }
    catch {
        Write-Error "Failed to create or validate secret scope: $($_.Exception.Message)"
        exit 1
    }

    Write-Host "loading Json Payload to Create Databricks Cluster"
    # Build JSON payload
$clusterPayload = @{
    cluster_name        = "General Purpose Cluster"
    spark_version       = "15.4.x-scala2.12"
    spark_conf          = @{
        "spark.sql.ansi.enabled" = "true"
        "fs.azure.account.key.$StorageAccountName.dfs.core.windows.net" = "{{secrets/$SecretScopeName/$($StorageAccountName)rawaccesskey}}"
    }
    azure_attributes    = @{
        availability = "SPOT_WITH_FALLBACK_AZURE"
    }
    node_type_id        = "Standard_D4ds_v5"
    autotermination_minutes = 20
    data_security_mode  = "DATA_SECURITY_MODE_AUTO"
    runtime_engine      = "STANDARD"
    kind                = "CLASSIC_PREVIEW"
    is_single_node      = $false
    autoscale           = @{
        min_workers = 1
        max_workers = 4
    }
} | ConvertTo-Json -Depth 10

    $headers = @{
        "Authorization" = "Bearer $DataBricksADDToken"
        "Content-Type"  = "application/json"
    }

    try {
        Write-Output "Creating databricks cluster [$DataBricksClusterName]..."
        $response = Invoke-WebRequest -Uri "$DataBricksWorkspaceURL/api/2.1/clusters/create" -Method POST -Headers $headers -Body $clusterPayload
        $response.Content 
        Write-Output "Databricks cluster [$DataBricksClusterName] is created succesfully"
    }
    catch {
        Write-Error "Failed to create Data Bricks Cluster: $($_.Exception.Message)"
        exit 1
    }

    Write-Output "Starting Databricks notebooks deployment process"
    # Data Bricks Config File Path
    $DataBricksConfigFilePath = "deploymentFiles\postdeploy_artifacts\azure.databricks"
    $DataBricksNoteBooksConfigsFilePath = $DataBricksConfigFilePath + '\python\notebooks'
    if (-not (Test-Path $DataBricksConfigFilePath)) {
        throw "Databricks artifacts folder not found at $DataBricksConfigFilePath"
    }

    # Save current location
    $revertPath = Get-Location

    # Deploy notebooks
    Set-Location -Path $DataBricksNoteBooksConfigsFilePath
    Write-Output "Deploying Databricks bundle from $DataBricksNoteBooksConfigsFilePath ..."
    $deployOutput = databricks bundle deploy --target DEFAULT
    Set-Location -Path $revertPath

    if ($LASTEXITCODE -ne 0) {
        throw "Databricks deployment failed. Error: $deployOutput"
    }
    Write-Output "Databricks bundle deployed successfully."

    Write-Log "COMPLETED: Azure Data Bricks Deployment..."
}

#####################################################################################
### Azure SQL Metadata Deployment ########################################
#####################################################################################
function Deploy-SQlMetaData {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,
    
        [Parameter(Mandatory=$true)]
        [string]$TenantId
    )

    Write-Log "STARTED: Azure SQL Metadat Deployment..."
    $FirewallRuleName = "TempPublicIP"

    try {
        Write-Output "Getting Public IP..."
        $CurrentPublicIP = (Invoke-WebRequest -Uri "https://api.ipify.org").Content
        Write-Output "Current Public IP: $CurrentPublicIP"

        # 1. Add temporary firewall rule
        Write-Host "Adding temporary firewall rule for IP $CurrentPublicIP..."
        az sql server firewall-rule create `
            -g $ResourceGroupName `
            -s $SqlServerName `
            -n $FirewallRuleName `
            --start-ip-address $CurrentPublicIP `
            --end-ip-address $CurrentPublicIP | Out-Null

        # 2. Fetch SQL credentials from Key Vault
        $sqlUsernameSecret = "$SqlServerName-adminusername"
        $sqlPasswordSecret = "$SqlServerName-adminpassword"

        Write-Host "Fetching SQL credentials from Key Vault [$KeyVaultName]..."
        $sqlLogin = az keyvault secret show --name $sqlUsernameSecret --vault-name $KeyVaultName --query "value" -o tsv
        $sqlPassword = az keyvault secret show --name $sqlPasswordSecret --vault-name $KeyVaultName --query "value" -o tsv

        Write-Host "sqlLogin: $sqlLogin"
        Write-Host "sqlPassword: $sqlPassword"

        if (-not $sqlLogin -or -not $sqlPassword) {
            throw "Failed to retrieve SQL credentials from Key Vault."
        }

        $connectionString = "Server=tcp:$SqlServerName.database.windows.net,1433;Initial Catalog=$SqlDatabaseName;Persist Security Info=False;User ID=$sqlLogin;Password=$sqlPassword;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
        #Write-Host "connectionString: $connectionString"

        $DataBricksWorkspaceName = (az databricks workspace show --name $DataBricksServiceName --resource-group $ResourceGroupName --query "workspaceUrl" -o tsv)
        $DataBricksWorkspaceURL = "https://$DataBricksWorkspaceName"
        Write-Host "DataBricks Workspace URL: $DataBricksWorkspaceURL"


        $SQLDacpacFilePath = "deploymentFiles\postdeploy_artifacts"
        # 3. Deploy DACPACs
$dacpacs = @(
    @{ file = "metadata.common.dacpac"; vars = "/v:DatabricksWSName=$DatabricksWorkspaceName /v:DatabricksHost=$DataBricksWorkspaceURL /v:DLSName=$StorageAccountName /v:Environment=Dev /v:KeyVaultName=$KeyVaultName /v:RGName=$ResourceGroupName /v:SubscriptionID=$SubscriptionId" },
    #@{ file = "metadata.control.dacpac"; vars = "/v:Environment=Dev /v:RGName=$ResourceGroupName /v:SubscriptionID=$SubscriptionId /v:ADFName=$DataFactoryName /v:TenantID=$TenantId" },
    @{ file = "metadata.ingest.dacpac"; vars = "" },
    @{ file = "metadata.transform.dacpac"; vars = "" }
)

        foreach ($dacpac in $dacpacs) {
            $path = Join-Path $SQLDacpacFilePath $dacpac.file
            if (Test-Path $path) {
                Write-Host "Publishing DACPAC [$path]..."
                ./sqlpackage/sqlpackage /Action:Publish /SourceFile:$path /TargetConnectionString:"$connectionString" $dacpac.vars

                if ($LASTEXITCODE -eq 0) {
                    Write-Output "SqlPackage deployment succeeded"
                }
                else {
                    Write-Error "SqlPackage deployment failed (ExitCode=$LASTEXITCODE)"
                    exit $LASTEXITCODE
                }
            }
            else {
                Write-Warning "DACPAC [$path] not found, skipping."
            }
        }

        Write-Host "Removing temporary firewall rule..."
        az sql server firewall-rule delete -g $ResourceGroupName -s $SqlServerName -n $FirewallRuleName

        Write-Host "=== Deployment completed successfully ==="

    } catch {
        Write-Error "Deployment failed: $_"
        exit 1
    } finally {
        $sqlPassword = $null  # clear sensitive data
    }

    Write-Log "Completed: Azure SQL Metadat Deployment..."

}

# ========================== Main Execution ==========================
try {
    Write-Log "Starting deployment process" "INFO"
    
    # Authenticate
    Write-Log "Authenticating Environment with managed identity"
    az login --identity
    Connect-AzAccount -Identity
    $context = Get-AzContext

    # Extract Subscription ID and Tenant ID
    $SubscriptionId = $context.Subscription.Id
    $SubscriptionName = $context.Subscription.Name
    $TenantId = $context.Tenant.Id

    Write-Output "Subscription Name: $SubscriptionName"
    Write-Output "Subscription ID: $subscriptionId"
    Write-Output "Tenant ID: $TenantId"
    Write-Log "Authentication with managed identity Completed"
    
    # Execute deployment steps
    Deploy-DataFactory
    Deploy-DataBricksWorkspace
    Deploy-SQlMetaData -SubscriptionId $SubscriptionId -TenantId $TenantId
    
    Write-Log "Deployment completed successfully" "SUCCESS"
    exit 0
}
catch {
    Write-Log "Deployment failed: $($_.Exception.Message)" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
finally {
    Write-Log "Deployment process finished" "INFO"
}