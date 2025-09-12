param(
[string] $ResourceGroupName,
[string] $DataFactoryName
)

# Authenticate with managed identity
Connect-AzAccount -Identity

# Install the Azure Data Factory Tools module.
Write-Host "-ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName"
Write-Host "Install-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force -AllowClobber -Scope CurrentUser"
Install-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force -AllowClobber -Scope CurrentUser
Write-Host "Import the module to make its cmdlets available."
Import-Module -Name azure.datafactory.tools -RequiredVersion 1.8.0 -Force
Get-Module -Name Az.Accounts -ListAvailable

$zipUrl = "https://github.com/CloudFormations/CF.Marketplace/raw/refs/heads/develop_powershell/products/cf.cumulus/temp/postdeploy_artifacts.zip"
$tempPath = "deploymentFiles"

Invoke-WebRequest -Uri $zipUrl -OutFile "$tempPath.zip"
Expand-Archive -Path "$tempPath.zip" -DestinationPath $tempPath -Force

# Get Deployment Objects and Params files
$scriptPath = "deploymentFiles\postdeploy_artifacts\azure.datafactory"

#$options = New-AdfPublishOption
#$options.CreateNewInstance = $false
#$options.Excludes.Add("trigger.*")
#$options.Excludes.Add("factory.*")

Publish-AdfV2FromJson -RootFolder "$scriptPath" -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Location "centralus" -Stage "install"

Write-Host "Data Factory objects deployed successfully."