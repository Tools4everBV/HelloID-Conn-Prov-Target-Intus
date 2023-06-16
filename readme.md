# HelloID-Conn-Prov-Target-Intus-Inplanning

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="assets/logo.png">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-Intus-Inplanning_ is a _target_ connector. The Intus Inplanning connector facilitates the creation, updating, enabling, and disabling of user accounts in Intus Inplanning. Additionally, it grants and revokes roles as entitlements to the user account.

| Endpoint                                          | Description                                   |
| ------------------------------------------------- | --------------------------------------------- |
| /api/token                                        | Gets the Token to connect with the api (POST) |
| /api/users/$($aRef)                               | get user based on the account reference (GET) |
| /api/users                                        | creates and updates the user (POST), (PUT)    |

The following lifecycle events are available:

| Event           | Description                                     | Notes                                                       |
|-----------------|-------------------------------------------------|------------------------------------------------------------ |
| create.ps1      | Create (or update) and correlate an Account     | -                                                           |
| update.ps1      | Update the Account                              | -                                                           |
| enable.ps1      | Enable the Account                              | -                                                           |
| disable.ps1     | Disable the account                             | -                                                           |
| delete.ps1      | No delete script available / Supported          | -                                                           |
| permission.ps1  | Retrieves entitlements                          | -                                                           |
| grant.ps1       | Grants and updates entitlements to the account  | This script is also used for the update in the entitlements |
| revoke.ps1      | Revokes entitlements to the account             | -                                                           |


## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting       | Description                             | Mandatory   |
| ------------- | --------------------------------------- | ----------- |
| Client id     | The Client id to connect to the API     | Yes         |
| Client secret | The Client Secret to connect to the API | Yes         |
| BaseUrl       | The URL to the API                      | Yes         |

### Prerequisites
 - Before using this connector, ensure you have the appropriate Client ID and Client Secret in order to connect to the API.

### Remarks
- Set the number of concurrent actions to 1. Otherwise, the 'get token' operation of one run will interfere with that of another run.
- The username cannot be modified in Intus Inplanning or helloId since it serves as the account reference.

## Permissions Remarks
- A user in Intus Inplanning can have multiple roles with the same name. These roles cannot be managed by HelloID. The HelloID connector only supports managing unique role names.
- The creation and update of entitlements utilize the same script, named grant.ps1.
- The connector uses a pre-defined set of entitlements that are created in Intus Inplanning
- The connector exclusively assigns a start date when a new entitlement is appended to an account. The start date remains unaltered when the user's entitlement is subsequently updated.
- The grant script does not establish the end date; instead, the business rules handle the removal of entitlement when it becomes unnecessary. It is possible to modify this process to assign the attribute 'endDate'.
- The permission script utilizes placeholder, for now only ({{costCenterOwn}}) in implememted, which will be substituted with a value from the primary contract. It is important to note that this value must be a recognized and established value within Intus Inplanning.
- The permission script employs an inline JSON object to retrieve the permissions. Alternatively, it is possible to obtain this information from a file using the following command: ```$jsonPermissions = Get-Content "C:\IntusPermissions.json" | ConvertFrom-Json```. Please note that an agent is required to perform this operation.
- When working with inline permissions in the permission.ps1 script, utilize the following structure:


```JSON
[
    {
        "Admin": {
            "role": "Admin",
            "resourceGroup": "Company",
            "exchangeGroup": "Company",
            "shiftGroup": "Diensten",
            "worklocationGroup": null,
            "userGroup": "n.v.t."
        }
    }
]
```

#### Creation / correlation process

A new functionality is the possibility to update the account in the target system during the correlation process. By default, this behavior is disabled. Meaning, the account will only be created or correlated.

You can change this behavior by adjusting the updatePersonOnCorrelate within the configuration

> Be aware that this might have unexpected implications.

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1481-helloid-conn-prov-target-intus)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/