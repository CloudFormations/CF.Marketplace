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

.PARAMETER DatabricksWorkspaceName
    Databricks workspace name

.PARAMETER DatabricksWorkspaceURL
    Databricks workspace URL (without https://)

.PARAMETER StorageAccountName
    Azure Storage account name

.PARAMETER SubscriptionId
    Azure subscription Id

.PARAMETER DataFactoryName
    Azure Data Factory name

.PARAMETER TenantId
    Azure Tenant Id

.PARAMETER SourceFolderPath
    Path containing DACPAC files

.PARAMETER DeploymentIp
    IP to whitelist during deployment
#>

$ResourceGroupName = $env:ResourceGroupName
$SqlServerName = $env:SqlServerName
$SqlDatabaseName = $env:SqlDatabaseName
$KeyVaultName = $env:KeyVaultName
$StorageAccountName = $env:StorageAccountName
$DataBricksServiceName = $env:DataBricksServiceName
$DataFactoryName = $env:DataFactoryName
$PostDeployDownloadArtifactsURL = $env:PostDeployDownloadArtifactsURL

Invoke-WebRequest -Uri "https://aka.ms/InstallAzureCLIDeb" -OutFile "azurecli-install.sh"
bash ./azurecli-install.sh
az --version
az login --identity
Connect-AzAccount -Identity
$context = Get-AzContext

# Extract Subscription ID and Tenant ID
$SubscriptionId = $context.Subscription.Id
$SubscriptionName = $context.Subscription.Name
$TenantId = $context.Tenant.Id

Write-Output "Subscription Name: $subscriptionName"
Write-Output "Subscription ID: $subscriptionId"
Write-Output "Tenant ID: $tenantId"

# Download & unzip SqlPackage
Write-Output "Installing SqlPackage on Linux..."
$installPath = "sqlpackage"
# download zip
Invoke-WebRequest -Uri "https://aka.ms/sqlpackage-linux" -OutFile "$installPath.zip" -UseBasicParsing
Expand-Archive -Path "$installPath.zip" -DestinationPath $installPath -Force -ErrorAction Stop

Install-Module -Name SqlServer -Force -Scope CurrentUser

try {
    Write-Host "=== Starting SQL Server Metadata Deployment ==="

    $publicIp = (Invoke-WebRequest -Uri "https://api.ipify.org").Content
    Write-Output "Current Public IP: $publicIp"


    # 1. Add temporary firewall rule
    Write-Host "Adding temporary firewall rule for IP $publicIp..."
    az sql server firewall-rule create `
        -g $ResourceGroupName `
        -s $SqlServerName `
        -n "CumulusDeploymentIPRequirement" `
        --start-ip-address $publicIp `
        --end-ip-address $publicIp | Out-Null

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
     Write-Host "connectionString: $connectionString"
    # Download and unzip the post-deployment artifact files from the repo
    $tempPath = "deploymentFiles"

    Invoke-WebRequest -Uri $PostDeployDownloadArtifactsURL -OutFile "$tempPath.zip"
    Expand-Archive -Path "$tempPath.zip" -DestinationPath $tempPath -Force

    Write-Host "Post-deployment artifacts downloaded and extracted to $tempPath"

    $DataBricksWorkspaceName = (az databricks workspace show --name $DataBricksServiceName --resource-group $ResourceGroupName --query "workspaceUrl" -o tsv)
    $DataBricksWorkspaceURL = "https://$DataBricksWorkspaceName"
    Write-Host "DataBricks Workspace URL: $DataBricksWorkspaceURL"


    $sourceFolderPath = "deploymentFiles\postdeploy_artifacts"
    # 3. Deploy DACPACs
    $dacpacs = @(
        @{ file = "metadata.common.dacpac"; vars = "/v:DatabricksWSName=$DatabricksWorkspaceName /v:DatabricksHost=https://$DataBricksWorkspaceName /v:DLSName=$StorageAccountName /v:Environment=Dev /v:KeyVaultName=$KeyVaultName /v:RGName=$ResourceGroupName /v:SubscriptionID=$SubscriptionId" },
        @{ file = "metadata.control.dacpac"; vars = "/v:Environment=Dev /v:RGName=$ResourceGroupName /v:SubscriptionID=$SubscriptionId /v:ADFName=$DataFactoryName /v:TenantID=$TenantId" },
        @{ file = "metadata.ingest.dacpac"; vars = "" },
        @{ file = "metadata.transform.dacpac"; vars = "" }
    )

    foreach ($dacpac in $dacpacs) {
        $path = Join-Path $SourceFolderPath $dacpac.file
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

    # 4. Set Azure AD Admin
    Write-Host "Setting current user as SQL AD Admin..."
    $userDetails = az ad signed-in-user show --query userPrincipalName -o tsv
    $userId = az ad signed-in-user show --query id -o tsv
    az sql server ad-admin create --resource-group $ResourceGroupName --server $SqlServerName --display-name $userDetails --object-id $userId | Out-Null

    # 5. Grant ADF access to SQL
    Write-Host "Granting ADF [$KeyVaultName] access to SQL [$SqlServerName]..."
    $accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
    $sqlServerNameFull = "$SqlServerName.database.windows.net"

$query = @"
IF NOT EXISTS (SELECT * FROM sys.sysusers WHERE name = '$KeyVaultName')
BEGIN
    CREATE USER [$KeyVaultName] FROM EXTERNAL PROVIDER;
END

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE type = 'R' AND name = 'db_cumulususer')
BEGIN
    CREATE ROLE [db_cumulususer];
END

GRANT EXECUTE, SELECT, CONTROL, ALTER ON SCHEMA::[control] TO [db_cumulususer];
GRANT EXECUTE, SELECT, CONTROL, ALTER ON SCHEMA::[ingest] TO [db_cumulususer];
GRANT EXECUTE, SELECT, CONTROL, ALTER ON SCHEMA::[transform] TO [db_cumulususer];

ALTER ROLE [db_cumulususer] ADD MEMBER [$KeyVaultName];
"@

    Invoke-Sqlcmd -ServerInstance $sqlServerNameFull -Database $SqlDatabaseName -AccessToken $accessToken -Query $query

    # 6. Cleanup firewall rule
    Write-Host "Removing temporary firewall rule..."
    az sql server firewall-rule delete `
        -g $ResourceGroupName `
        -s $SqlServerName `
        -n "CumulusDeploymentIPRequirement" -y | Out-Null

    Write-Host "=== Deployment completed successfully ==="

} catch {
    Write-Error "Deployment failed: $_"
    exit 1
} finally {
    $sqlPassword = $null  # clear sensitive data
}