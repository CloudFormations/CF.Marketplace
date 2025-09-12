param(
[string] $ResourceGroupName,
[string] $SqlServerName,
[string] $SqlDatabaseName,
[string] $DataFactoryName,
[string] $keyVaultName
)

Connect-AzAccount -Tenant 'f95c9998-053d-475f-95d9-09f968c372bf' -SubscriptionId '546e6297-9c56-4499-a3c9-8ee2ddb83a5c'

Write-Output "Getting Public IP..."
$CurrentPublicIP = (Invoke-WebRequest -Uri "https://api.ipify.org").Content
Write-Output "Current Public IP: $CurrentPublicIP"

$FirewallRuleName = "TempUserPublicIP"

# 1. Add temporary firewall rule
Write-Host "Adding temporary firewall rule for IP $CurrentPublicIP..."

New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -FirewallRuleName $FirewallRuleName -StartIpAddress $CurrentPublicIP -EndIpAddress $CurrentPublicIP

# 4. Set Azure AD Admin
Write-Host "Setting current user as SQL AD Admin..."
#$userDetails = az ad signed-in-user show --query userPrincipalName -o tsv
#$userId = az ad signed-in-user show --query id -o tsv
#az sql server ad-admin create --resource-group $ResourceGroupName --server $SqlServerName --display-name $CurrentUserManagedIdentityName --object-id $CurrentUserManagedIdentityID | Out-Null

# 5. Grant ADF access to SQL
Write-Host "Granting ADF [$KeyVaultName] access to SQL [$SqlServerName]..."
$accessToken = (Get-AzAccessToken -ResourceUrl https://database.windows.net).Token
Write-Host "Managed Identity Access Token: $accessToken"
$sqlServerNameFull = "$SqlServerName.database.windows.net"

$DataFactoryName2 = "abcd"

$query = @"
-- Cumulus Additional Database Data Source Pre-requisites
IF NOT EXISTS (SELECT * FROM sys.sysusers WHERE name = '$DataFactoryName2')
BEGIN
	CREATE USER [$DataFactoryName2] FROM EXTERNAL PROVIDER;
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
ADD MEMBER [$DataFactoryName2];
"@

Invoke-Sqlcmd -ServerInstance $sqlServerNameFull -Database $SqlDatabaseName -AccessToken $accessToken -Query $query

# 6. Cleanup firewall rule
Write-Host "Removing temporary firewall rule..."
Remove-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlServerName -FirewallRuleName $FirewallRuleName -Force

Write-Host "=== Deployment completed successfully ==="