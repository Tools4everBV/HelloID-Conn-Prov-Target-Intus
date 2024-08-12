
# HelloID-Conn-Prov-Target-Intus-Inplanning

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/intus-logo.png">
</p>


## Table of contents

- [HelloID-Conn-Prov-Target-Intus-Inplanning](#helloid-conn-prov-target-intus-inplanning)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
      - [Correlation configuration](#correlation-configuration)
      - [Field mapping](#field-mapping)
    - [Connection settings](#connection-settings)
    - [Prerequisites](#prerequisites)
    - [Remarks](#remarks)
      - [Permissions Remarks](#permissions-remarks)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Intus-Inplanning_ is a _target_ connector. The Intus Inplanning connector facilitates the creation, updating, enabling, and disabling of user accounts in Intus Inplanning. Additionally, it grants and revokes roles as entitlements to the user account.

| Endpoint                                          | Description                                   |
| ------------------------------------------------- | --------------------------------------------- |
| /api/token                                        | Gets the Token to connect with the api (POST) |
| /api/users/AccountReference                       | get user based on the account reference (GET) |
| /api/users                                        | creates and updates the user (POST), (PUT)    |

The following lifecycle actions are available:

| Action                 | Description                                      |
| ---------------------- | ------------------------------------------------ |
| create.ps1             | PowerShell _create_ lifecycle action             |
| delete.ps1             | -     |
| disable.ps1            | PowerShell _disable_ lifecycle action            |
| enable.ps1             | PowerShell _enable_ lifecycle action             |
| update.ps1             | PowerShell _update_ lifecycle action             |
| grantPermission.ps1    | PowerShell _grant_ lifecycle action              | This script is also used for the update in the entitlements
| revokePermission.ps1   | PowerShell _revoke_ lifecycle action             |
| permissions.ps1        | PowerShell _permissions_ lifecycle action        |
| resources.ps1          | -       |
| configuration.json     | Default _[Configuration.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Intus-Inplanning/blob/main/configuration.json)_ |
| fieldMapping.json      | Default _[FieldMapping.json](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Intus-Inplanning/blob/main/fieldMapping.json)_   |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _Intus-Inplanning_ to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | Not Supported |
    | Account correlation field | `username`                                |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

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


#### Permissions Remarks
- A user in Intus Inplanning can have multiple roles with the same name. These roles cannot be managed by HelloID. The HelloID connector only supports managing unique role names.
- The creation and update of entitlements utilize the same script, named grant.ps1.
- The connector uses a pre-defined set of entitlements that are created in Intus Inplanning
- The connector exclusively assigns a start date when a new entitlement is appended to an account. The start date remains unaltered when the user's entitlement is subsequently updated.
- The grant script does not establish the end date; instead, the business rules handle the removal of entitlement when it becomes unnecessary. It is possible to modify this process to assign the attribute 'endDate'.
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


- You can utilize a variable within the JSON permissions, such as your own CostCenter, for example. Currently, an example variable named `{{costCenterOwn}}` AND `{{LocationOwn}}` is included in the grant script. You can integrate this variable name into your JSON within the permission script. Additionally, an example is provided in the grant script to substitute the variable with a value from the contract that is 'incondition'. It's important to note that this value must be recognized and established within Intus.

**Example of the JSON permissions and the PowerShell code snippet**
```JSON
   "resourceGroup": "{{costCenterOwn}}",
```

```PowerShell
foreach ($contract in $personContext.Person.Contracts) {
  ....
        $mappedProperty = $contract.CostCenter.Name
  
        foreach ($property in $newRole.PSObject.Properties) {
            if ($property.value -eq '{{costCenterOwn}}') {
                if ([string]::IsNullOrEmpty($mappedProperty)) {
                    throw 'Permission expects [{{costCenterOwn}}] to grant the permission the specified cost center is empty'
                }
                $newRole."$($property.name)" = $mappedProperty
                Write-verbose "Replacing property: [$($property.name)] value: [{{costCenterOwn}}] with [$($mappedProperty)]"
            }
        }
  ...
}
```

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1481-helloid-conn-prov-target-intus)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

