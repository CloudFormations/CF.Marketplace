param(
[string] $ResourceGroupName,
[string] $FunctionAppName,
[string] $keyVaultName
)

Write-Output "Fetching function app master key..."
$MASTER_KEY=$(az functionapp keys list --name $FunctionAppName --resource-group $ResourceGroupName --query masterKey -o tsv)

Write-Output "Storing master key in Key Vault..."
az keyvault secret set --vault-name $keyVaultName --name "cumulusfunctionsKey" --value "$MASTER_KEY"