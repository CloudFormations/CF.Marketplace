param(
[string] $ResourceGroupName,
[string] $DataBricksServiceName,
[string] $SecretScopeName,
[string] $KeyVaultID,
[string] $KeyVaultURI,
[string] $StorageAccountName,
[string] $DownloadArtifactsURL
)

Invoke-WebRequest -Uri "https://aka.ms/InstallAzureCLIDeb" -OutFile "azurecli-install.sh"
bash ./azurecli-install.sh
az --version

bash -c "apt-get update && apt-get install -y unzip"
# Install Databricks CLI
bash -c "curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh"

# Add Databricks CLI to PATH
$env:PATH += ":$HOME/.databricks/bin"

# Verify installation
databricks --version
az login --identity

$DataBricksClusterName = "General Purpose Cluster"

Write-Host "ResourceGroupName: $ResourceGroupName"
Write-Host "DataBricksServiceName: $DataBricksServiceName"
Write-Host "SecretScopeName: $SecretScopeName"
Write-Host "keyVaultDeployURI: $KeyVaultURI"
Write-Host "keyVaultDeployID: $KeyVaultID"
Write-Host "StorageAccountName: $StorageAccountName"

# Get AAD token for Databricks
$DataBricksADDToken = az account get-access-token --resource 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d --query accessToken --output tsv

if (-not $DataBricksADDToken) {
    throw "Failed to acquire AAD token for Databricks."
}

# Configure .databrickscfg
Write-Host "Configuring databrickscfg"
$DataBricksWorkspaceName = (az databricks workspace show --name $DataBricksServiceName --resource-group $ResourceGroupName --query "workspaceUrl" -o tsv)
$DataBricksWorkspaceURL = "https://$DataBricksWorkspaceName"
Write-Host "DataBricks Workspace URL: $DataBricksWorkspaceURL"

# Configure databricks config profile
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
        "fs.azure.account.key.$storageAccountName.dfs.core.windows.net" = "{{secrets/$secretScopeName/$($storageAccountName)rawaccesskey}}"
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

# Download artifacts
$TempPath = "deploymentFiles"

Write-Output "Downloading artifacts from $DownloadArtifactsURL ..."
Invoke-WebRequest -Uri $DownloadArtifactsURL -OutFile "$TempPath.zip" -ErrorAction Stop
Write-Output "Download completed."

# Extract zip
Write-Output "Extracting artifacts to $TempPath ..."
Expand-Archive -Path "$TempPath.zip" -DestinationPath $TempPath -Force -ErrorAction Stop
Write-Output "Extraction completed."

Write-Output "Starting Databricks notebooks deployment process"

# Locate Databricks folder
$scriptPath = "deploymentFiles\postdeploy_artifacts\azure.databricks"
$sourcePath = $scriptPath + '\python\notebooks'
if (-not (Test-Path $scriptPath)) {
    throw "Databricks artifacts folder not found at $scriptPath"
}

# Save current location
$revertPath = Get-Location

# Deploy notebooks
Set-Location -Path $sourcePath
Write-Output "Deploying Databricks bundle from $sourcePath ..."
$deployOutput = databricks bundle deploy --target DEFAULT
Set-Location -Path $revertPath

if ($LASTEXITCODE -ne 0) {
    throw "Databricks deployment failed. Error: $deployOutput"
}
Write-Output "Databricks bundle deployed successfully."