#!/bin/bash
ResourceGroupName=$1
FunctionAppName=$2
KeyVaultName=$3

echo "Fetching function app master key..."
MASTER_KEY=$(az functionapp keys list --name "$FunctionAppName" --resource-group "$ResourceGroupName" --query masterKey -o tsv)

echo "Storing master key in Key Vault..."
az keyvault secret set --vault-name "$KeyVaultName" --name "cumulusfunctionsKey" --value "$MASTER_KEY"