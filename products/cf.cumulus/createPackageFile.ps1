# Define the source folder and files to copy
$packageFolder = Join-Path $PSScriptRoot "package"
$file1 = "createUiDefinition.json"  
$file2 = "mainTemplate.json"

# Define the destination zip file
$zipFile = Join-Path $PSScriptRoot "cfcumulus.zip"

# Create a temporary folder to stage files
$tempFolder = Join-Path $PSScriptRoot "temp_zip"
if (Test-Path $tempFolder) { Remove-Item $tempFolder -Recurse -Force }
New-Item -ItemType Directory -Path $tempFolder | Out-Null

# Copy the files to the temp folder
Copy-Item -Path (Join-Path $packageFolder $file1) -Destination $tempFolder
Copy-Item -Path (Join-Path $packageFolder $file2) -Destination $tempFolder

# Create the zip archive
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
Compress-Archive -Path (Join-Path $tempFolder "*") -DestinationPath $zipFile

# Clean up temp folder
Remove-Item $tempFolder -Recurse -Force

Write-Host "Created archive: $zipFile"