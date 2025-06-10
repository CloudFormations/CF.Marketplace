# Azure Marketplace Offering

This project contains the necessary files to deploy an Azure Marketplace offering using Bicep and Azure Resource Manager (ARM) templates.

[![Deploy To Azure](./deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FCloudFormations%2FCF.Cumulus%2Frefs%2Fheads%2Fdevelop_marketplace%2Finfrastructure%2Fmain.json)

[![Deploy To Azure](./deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FCloudFormations%2FCF.Cumulus%2Frefs%2Fheads%2Fdevelop_marketplace%2Finfrastructure%2Fmarketplace%2FadfTemplate.json)

### Compiling the BiCep

```
bicep build ".\infrastructure\main.bicep"
```
```
pid-c7c02b4c-2b89-4086-a4fc-a436ef37c78f-partnercenter

Package acceptance validation error: AzureAppCannotAddTrackingId The package you have uploaded utilizes resources of type Microsoft.Resources/deployments for purposes other than customer usage attribution. Partner Center will be unable to add a customer usage attribution id on your behalf in this case. Please add a new resource of type Microsoft.Resources/deployments and add the tracking ID visible in Partner Center on your plan's Technical Configuration page. To learn more about tracking customer usage attribution please see https://aka.ms/aboutinfluencedrevenuetracking. Error code: PAC-AzureAppCannotAddTrackingId
```

## Creating the UI Definition

[https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/SandboxBlade](https://portal.azure.com/#view/Microsoft_Azure_CreateUIDef/SandboxBlade)

## Project Structure

- **main.bicep**: Contains the main infrastructure deployment logic for the Azure Marketplace offering. It defines parameters, variables, and modules for deploying various Azure resources such as Key Vault, Storage, Data Factory, and more.

- **mainTemplate.json**: Serves as the entry point for the ARM template. It includes the parameters that will be passed to the `main.bicep` file and defines the resources to be deployed.


## Steps to Create Marketplace ARM Template

- Build BiCep.
- Copy contents to mainTemplate.json.
- Refactor rgName to use managed resource group value. [resourceGroup().name]
- Remove the creation of the internal resource group.
- Remove all references to the resource group in the dependsOn clauses.
- Add the partner attribution ID values.
- Add a linked ARM template to deploy ADF artifacts.



/*
https://portal.azure.com/#view/Microsoft_Azure_Marketplace/GalleryItemDetailsBladeNopdl/id/cloudformations.azap-cumulus-preview/resourceGroupId//resourceGroupLocation//dontDiscardJourney~/false/_provisioningContext~/%7B%22initialValues%22%3A%7B%22subscriptionIds%22%3A%5B%221b2b1db2-3735-4a51-86a5-18fa41b8bb49%22%2C%227613a611-94d8-4c42-9a7a-db258ff1ff2e%22%5D%2C%22resourceGroupNames%22%3A%5B%5D%2C%22locationNames%22%3A%5B%22uksouth%22%5D%7D%2C%22telemetryId%22%3A%2232baebcd-13f9-4478-9208-03bfdd50d00e%22%2C%22marketplaceItem%22%3A%7B%22categoryIds%22%3A%5B%5D%2C%22id%22%3A%22Microsoft.Portal%22%2C%22itemDisplayName%22%3A%22NoMarketplace%22%2C%22products%22%3A%5B%5D%2C%22version%22%3A%22%22%2C%22productsWithNoPricing%22%3A%5B%5D%2C%22publisherDisplayName%22%3A%22Microsoft.Portal%22%2C%22deploymentName%22%3A%22NoMarketplace%22%2C%22launchingContext%22%3A%7B%22telemetryId%22%3A%2232baebcd-13f9-4478-9208-03bfdd50d00e%22%2C%22source%22%3A%5B%5D%2C%22galleryItemId%22%3A%22%22%7D%2C%22deploymentTemplateFileUris%22%3A%7B%7D%2C%22uiMetadata%22%3Anull%7D%7D
*/
