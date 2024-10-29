################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-GrantPermission
# PowerShell V2
################################################

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-AccessToken {
    [CmdletBinding()]
    param (
    )
    process {
        try {
            $tokenHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
            $tokenHeaders.Add('Content-Type', 'application/x-www-form-urlencoded')

            $splatGetTokenParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/token"
                Headers = $tokenHeaders
                Method  = 'POST'
                Body    = @{
                    client_id     = $actionContext.Configuration.clientId
                    client_secret = $actionContext.Configuration.clientSecret
                    grant_type    = 'client_credentials'
                }
            }
            Write-Output (Invoke-RestMethod @splatGetTokenParams).access_token
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
function Resolve-Intus-InplanningError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if ($ErrorObject.ErrorDetails) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails
            $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails
        }
        elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
            }
        }
        try {
            $httpErrorObj.FriendlyMessage = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json).error_description
        }
        catch {
            #displaying the old message if an error occurs during an API call, as the error is related to the API call and not the conversion process to JSON.
        }
        Write-Output $httpErrorObj
    }
}
#endregion


try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-verbose "Verifying if a Intus-Inplanning account for [$($personContext.Person.DisplayName)] exists"
    $accessToken = Get-AccessToken
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('Authorization', 'Bearer ' + $accessToken)

    try {
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/users/$($actionContext.References.Account)"
            Headers = $headers
            Method  = 'GET'
        }
        $correlatedAccount = Invoke-RestMethod @splatGetUserParams



    }
    catch {
        if ( -not ($_.ErrorDetails.Message -match '211 - Object does not exist')) {
            throw "Cannot get user error: [$($_.Exception.Message)]"
        }
    }

    if ($null -ne $correlatedAccount) {
        Write-verbose "current roles: $($correlatedAccount.roles | convertto-json)"
        [System.Collections.ArrayList]$currentRoles = $correlatedAccount.roles.psobject.copy()
    }
    else {
        Throw "Intus-Inplanning account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted"
    }


    # Sub-permissions
    foreach ($contract in $personContext.Person.Contracts) {
        $newRole = $actionContext.References.Permission.Reference.psobject.copy()

        #clear enddate when granting role
        $newRole | add-member -type noteproperty -name endDate -value $null -force

        if ($contract.Context.InConditions -OR $actionContext.DryRun) {
            # Example Replacing placeholders in the permission with the value's from HelloId contract
            # Custom Permissions mapping
            $mappedProperty = $contract.Department.ExternalId

            $replaceVariable = '{{costCenterOwn}}'

            foreach ($property in $newRole.PSObject.Properties) {
                if ($property.value -like "*$replaceVariable*") {
                    if ([string]::IsNullOrEmpty($mappedProperty)) {
                        throw 'Permission expects [$replaceVariable] to grant the permission the specified cost center is empty'
                    }
                    $newRole."$($property.name)" = $newRole."$($property.name)" -replace ($replaceVariable, $mappedProperty)
                    Write-verbose "Replacing property: [$($property.name)] value: [$replaceVariable] with [$($mappedProperty)]"
                }
            }

            #locationOwn
            $mappedProperty = $contract.Division.Name
            $replaceVariable = '{{locationOwn}}'

            foreach ($property in $newRole.PSObject.Properties) {
                if ($property.value -like "*$replaceVariable*") {
                    if ([string]::IsNullOrEmpty($mappedProperty)) {
                        throw 'Permission expects [$replaceVariable] to grant the permission the specified cost center is empty'
                    }
                    $newRole."$($property.name)" = $newRole."$($property.name)" -replace ($replaceVariable, $mappedProperty)
                    Write-verbose "Replacing property: [$($property.name)] value: [$replaceVariable] with [$($mappedProperty)]"
                }
            }

    
            #locationCode
            $mappedProperty = $contract.location.name          

            $replaceVariable = '{{locationCode}}'

            foreach ($property in $newRole.PSObject.Properties) {
                if ($property.value -like "*$replaceVariable*") {
                    if ([string]::IsNullOrEmpty($mappedProperty)) {
                        throw 'Permission expects [$replaceVariable] to grant the permission the specified cost center is empty'
                    }
                    $newRole."$($property.name)" = $newRole."$($property.name)" -replace ($replaceVariable, $mappedProperty)
                    Write-verbose "Replacing property: [$($property.name)] value: [$replaceVariable] with [$($mappedProperty)]"
                }
            }

            #department
            $mappedProperty = $contract.department.externalID          

            $replaceVariable = '{{departmentCode}}'

            foreach ($property in $newRole.PSObject.Properties) {
                if ($property.value -like "*$replaceVariable*") {
                    if ([string]::IsNullOrEmpty($mappedProperty)) {
                        throw 'Permission expects [$replaceVariable] to grant the permission the specified cost center is empty'
                    }
                    $newRole."$($property.name)" = $newRole."$($property.name)" -replace ($replaceVariable, $mappedProperty)
                    Write-verbose "Replacing property: [$($property.name)] value: [$replaceVariable] with [$($mappedProperty)]"
                }
            }


            # Add or update user with role First check role+resource group
             if ($actionContext.DryRun -eq $true) {
                Write-Warning "current: $($currentRoles | convertto-json)"
             }

            $existingRole = $currentRoles.Where({ $_.role -eq $newRole.role -AND $_.resourceGroup -eq $newRole.resourceGroup })
            if ($existingRole.count -gt 1) {
                throw "Multiple roles with the same name found [$($newRole.role)]"
            }
            elseif ($existingRole.count -eq 0) {
                $action = "GrantPermission"
                $currentRoles += $newRole
            }
            elseif ($existingRole.count -eq 1) {

                # Write-Warning "exist: $($existingRole | convertto-json)"
                # Write-Warning "new: $($newRole | convertto-json)"

                #compare existingrole with newRole for other changes.
                $splatCompareProperties = @{
                    ReferenceObject  = @(($existingRole | select-object).psobject.properties)
                    DifferenceObject = @(($newRole  | select-object).psobject.properties)
                }           
                $changedProperties = $null
                $changedProperties = (Compare-Object @splatCompareProperties -PassThru)
                $oldProperties = $changedProperties.Where( { $_.SideIndicator -eq "<=" })
                $newProperties = $changedProperties.Where( { $_.SideIndicator -eq "=>" })

                if (($newProperties | measure-object).count -gt 0) {
                    if ($actionContext.DryRun -eq $true) {
                        Write-Warning "[DRYRUN] update role; changed properties : $($newProperties.name -join("; ")))"
                    }
                    $action = "GrantPermission"
                    $currentRoles = $existingRole = $currentRoles.Where({ -NOT ($_.role -eq $newRole.role -AND $_.resourceGroup -eq $newRole.resourceGroup) })
                    $currentRoles += $newRole
                }
            }

            $SubPermissionsDisplayName = "$($newRole.role): $($newRole.resourceGroup)"
            $SubPermissionsReference = $newRole
            $exstingSubpermission = $outputContext.SubPermissions | where-object displayname -eq "$SubPermissionsDisplayName"

            if (($exstingSubpermission | measure-object).count -eq 0) {
                $outputContext.SubPermissions.Add([PSCustomObject]@{
                        DisplayName = $SubPermissionsDisplayName 
                        Reference   = $SubPermissionsReference
                    }
                )
            }

        }
    }

    #UPDATE USER
    switch ($action) {
        'GrantPermission' {
            $correlatedAccount.roles = @($currentRoles)

            $body = ($correlatedAccount | ConvertTo-Json -Depth 10)

            $splatUpdateUserParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/users"
                Headers     = $headers
                Method      = 'PUT'
                Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType = 'application/json;charset=utf-8'
            }
             Write-Warning " will set roles: $($correlatedAccount.roles | convertto-json)"
            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-RestMethod @splatUpdateUserParams -Verbose:$false
            }
            else {
                Write-Warning "[DRYRUN] will set roles: $($correlatedAccount.roles | convertto-json)"
            }


            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Grant permission [$($actionContext.References.Permission.DisplayName)] was successful"
                    IsError = $false
                })
        }
        'NoChanges' {
            Write-verbose "Nothing to change - returning subpermissions $($outputContext.SubPermissions.displayname -join("|"))"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Grant permission [$($actionContext.References.Permission.DisplayName)] skipped - NoChanges"
                    IsError = $false
                })
        }

    }

    $outputContext.Success = $true

}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Intus-InplanningError -ErrorObject $ex
        $auditMessage = "Could not grant Intus-Inplanning permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not grant Intus-Inplanning permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}


