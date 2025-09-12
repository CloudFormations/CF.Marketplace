 # Script to assign permissions to an existing UMI 
# The following required Microsoft Graph permissions will be assigned: 
#   User.Read.All
#   GroupMember.Read.All
#   Application.Read.All
#For More Info
##https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-azure-ad-user-assigned-managed-identity?view=azuresql


param(
[string] $tenantId,
[string] $MSIName
)

# Set the PSGallery as a trusted repository to avoid the "unsecure modules" warning.
# This is a one-time operation.
if ((Get-PSRepository -Name "PSGallery").InstallationPolicy -ne "Trusted") {
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
}

# Install modules, skipping the prompt for untrusted sources.
Write-Host "Installing Microsoft Graph modules..."
Install-Module -Name Microsoft.Graph.Authentication -Force -AllowClobber -Scope CurrentUser
Install-Module -Name Microsoft.Graph.Applications -Force -AllowClobber -Scope CurrentUser

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

$tenantId = "f95c9998-053d-475f-95d9-09f968c372bf"     # Your tenant ID
$MSIName = "functionZipDeployIdentity"                 # Name of your managed identity

# Log in as a user with the "Privileged Role Administrator" role
Connect-MgGraph -TenantId $tenantId -Scopes "AppRoleAssignment.ReadWrite.All,Application.Read.All"

# Search for Microsoft Graph
$MSGraphSP = Get-MgServicePrincipal -Filter "DisplayName eq 'Microsoft Graph'";
$MSGraphSP

$MSI = Get-MgServicePrincipal -Filter "DisplayName eq '$MSIName'" 
if($MSI.Count -gt 1)
{ 
Write-Output "More than 1 principal found with that name, please find your principal and copy its object ID. Replace the above line with the syntax $MSI = Get-MgServicePrincipal -ServicePrincipalId <your_object_id>"
Exit
}

# Get required permissions
$Permissions = @(
  "User.Read.All"
  "GroupMember.Read.All"
  "Application.Read.All"
)

# Find app permissions within Microsoft Graph application
$MSGraphAppRoles = $MSGraphSP.AppRoles | Where-Object {($_.Value -in $Permissions)}

# Assign the managed identity app roles for each permission
foreach($AppRole in $MSGraphAppRoles)
{
    $AppRoleAssignment = @{
	    principalId = $MSI.Id
	    resourceId = $MSGraphSP.Id
	    appRoleId = $AppRole.Id
    }

New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $AppRoleAssignment.PrincipalId -BodyParameter $AppRoleAssignment -Verbose
}