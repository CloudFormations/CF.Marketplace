param(
    [Parameter(Mandatory = $true)]
    [string]$DataBricksWorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$ManagedResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$DatabricksSKU
)

Write-Host "DataBricksWorkspaceName: $DataBricksWorkspaceName"
Write-Host "ResourceGroupName: $ResourceGroupName"
Write-Host "Location: $Location"
Write-Host "ManagedResourceGroupName: $ManagedResourceGroupName"
Write-Host "DatabricksSKU: $DatabricksSKU"

try {
    # 1. Authenticate with Managed Identity
    Write-Host "Authenticating with Managed Identity..."
    Connect-AzAccount -Identity -ErrorAction Stop

    # 2. Ensure provider is registered
    Write-Host "Ensuring Microsoft.Databricks provider is registered..."
    $provider = Get-AzResourceProvider -ProviderNamespace "Microsoft.Databricks"
    if ($provider.RegistrationState -ne "Registered") {
        Register-AzResourceProvider -ProviderNamespace "Microsoft.Databricks" -ErrorAction Stop
        Write-Host "Provider registered successfully."
    }
    else {
        Write-Host "Provider already registered."
    }

    # 3. Check if Databricks workspace already exists
    Write-Host "Checking if workspace [$DataBricksWorkspaceName] exists..."
    $workspace = Get-AzDatabricksWorkspace -ResourceGroupName $ResourceGroupName -Name $DataBricksWorkspaceName -ErrorAction SilentlyContinue

    if ($null -ne $workspace) {
        Write-Host "Workspace [$DataBricksWorkspaceName] already exists in [$ResourceGroupName]."
    }
    else {
        # 4. Create Databricks Workspace
        Write-Host "Creating new Databricks workspace..."
        $workspace = New-AzDatabricksWorkspace `
            -Name $DataBricksWorkspaceName `
            -ResourceGroupName $ResourceGroupName `
            -Location $Location `
            -ManagedResourceGroupName $ManagedResourceGroupName `
            -Sku $DatabricksSKU `
            -ErrorAction Stop

        Write-Host "Databricks workspace created successfully."
    }

    # 5. Show workspace details
    $workspace | Select-Object Name, SkuName, Location, ProvisioningState

    $getWorkspace =  Get-AzResource -ResourceGroupName $ResourceGroupName -ResourceType "Microsoft.Databricks/workspaces" -Name $DataBricksWorkspaceName
    $Id = $getWorkspace.id
    $Name = $getWorkspace.name
    $Url = $getWorkspace.Properties.workspaceUrl
    Write-Output "Databricks Workspace ID: $Id"
    Write-Output "Databricks Workspace Name: $Name"
    Write-Output "Databricks Workspace URL: $Url"

    # $DeploymentScriptOutputs = @{
    #     workspaceId   = $getWorkspace.id
    #     workspaceName = $getWorkspace.name
    #     workspaceUrl  = $getWorkspace.Properties.workspaceUrl
    # }

    # Save outputs to file
    # $DeploymentScriptOutputs | ConvertTo-Json -Depth 5 | Out-File -FilePath $env:AZ_SCRIPTS_OUTPUT_PATH -Encoding utf8

    $DeploymentScriptOutputs = @{
        workspaceId   = $getWorkspace.id
        workspaceName = $getWorkspace.name
        workspaceUrl  = $getWorkspace.properties.workspaceUrl
    }

    # Convert to JSON
    $jsonOutput = $DeploymentScriptOutputs | ConvertTo-Json -Depth 5

    if ($env:AZ_SCRIPTS_OUTPUT_PATH) {
        # Running inside Azure Deployment Script
        $jsonOutput | Out-File -FilePath $env:AZ_SCRIPTS_OUTPUT_PATH -Encoding utf8
        Write-Host "Output written to $env:AZ_SCRIPTS_OUTPUT_PATH"
    } else {
        # Running locally → just print
        Write-Host "AZ_SCRIPTS_OUTPUT_PATH not set. Printing output instead:"
        Write-Output $jsonOutput
    }

} catch {
    Write-Error "Failed: $($_.Exception.Message)"
    exit 1
}
