param(
[string] $ResourceGroupName,
[string] $FunctionAppName
)
$ZipUrl = "https://github.com/CloudFormations/CF.Marketplace/raw/refs/heads/develop_powershell/products/cf.cumulus/temp/azure.functionapp.zip"
Write-Output "Downloaded zip from $ZipUrl"
$TempZipPath = "$HOME/functionapp.zip"

Write-Output "Invoking-WebRequest URL"
Invoke-WebRequest -Uri $ZipUrl -OutFile $TempZipPath

Write-Output "Getting publishing profile for $FunctionAppName"
$publishingProfileXml = Get-AzWebAppPublishingProfile -ResourceGroupName $ResourceGroupName -Name $FunctionAppName -OutputFile null

Write-Output "publishingProfileXml"
$xml = [xml]$publishingProfileXml
$profile = $xml.publishData.publishProfile | Where-Object { $_.publishMethod -eq 'MSDeploy' }

$username = $profile.userName
$password = $profile.userPWD
#Write-Output "username: $username"
#Write-Output "password: $password"
Write-Output "https://$FunctionAppName.scm.azurewebsites.net/api/zipdeploy"
$publishUrl = "https://$FunctionAppName.scm.azurewebsites.net/api/zipdeploy"

Write-Output "Publishing to $publishUrl"
Invoke-RestMethod -Uri $publishUrl -Method POST -InFile $TempZipPath -ContentType "application/zip" -Headers @{Authorization = ("Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${username}:${password}")))}

#$output = "Deployment to $FunctionAppName complete."