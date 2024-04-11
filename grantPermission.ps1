################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-GrantPermission
# PowerShell V2
################################################

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
        } catch {
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
        } elseif ((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not([string]::IsNullOrWhiteSpace($streamReaderResponse))) {
                $httpErrorObj.ErrorDetails = $streamReaderResponse
                $httpErrorObj.FriendlyMessage = $streamReaderResponse
            }
        }
        try {
            $httpErrorObj.FriendlyMessage = ($httpErrorObj.FriendlyMessage | ConvertFrom-Json).error_description
        } catch {
            #displaying the old message if an error occurs during an API call, as the error is related to the API call and not the conversion process to JSON.
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information "Verifying if a Intus-Inplanning account for [$($personContext.Person.DisplayName)] exists"
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
    } catch {
        if ( -not ($_.ErrorDetails.Message -match '211 - Object does not exist')) {
            throw "Cannot get user error: [$($_.Exception.Message)]"
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'GrantPermission'
        $dryRunMessage = "Grant Intus-Inplanning entitlement: [$($actionContext.References.Permission.Reference)], will be executed during enforcement"
    } else {
        $action = 'NotFound'
        $dryRunMessage = "Intus-Inplanning account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted"
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Example Replacing placeholders in the permission with the value's from HelloId contract
    # Custom Permissions mapping
    $mappedProperty = $personContext.Person.PrimaryContract.CostCenter.Name
    foreach ($property in $actionContext.References.Permission.Reference.PSObject.Properties) {
        if ($property.value -eq '{{costCenterOwn}}') {
            if ([string]::IsNullOrEmpty($mappedProperty)) {
                throw 'Permission expects [{{costCenterOwn}}] to grant the permission the specified cost center is empty'
            }
            $actionContext.References.Permission.Reference."$($property.name)" = $mappedProperty
            Write-Information "Replacing property: [$($property.name)] value: [{{costCenterOwn}}] with [$($mappedProperty)]"
        }
    }

    # Add or update user with role
    $existingRole = $correlatedAccount.roles.Where({ $_.role -eq $actionContext.References.Permission.Reference.role })
    if ($existingRole.count -gt 1) {
        throw "Multiple roles with the same name found [$($actionContext.References.Permission.Reference.role)]"
    } elseif ($existingRole.count -eq 0) {
        $startDate = Get-Date -Format 'yyyy-MM-dd'
        $actionContext.References.Permission.Reference | Add-Member -MemberType NoteProperty -Name 'startDate' -Value $startDate
        $correlatedAccount.roles += $actionContext.References.Permission.Reference
    } else {
        # Possibly implement a comparison to verify whether an update is necessary instead of always performing an update.
        $existingRole | Add-Member -MemberType NoteProperty -Name 'endDate' -Value $null -Force
        foreach ($propertiesToUpdate in $actionContext.References.Permission.Reference.PSObject.Properties) {
            $existingRole | Add-Member -MemberType NoteProperty -Name "$($propertiesToUpdate.name)" -Value $propertiesToUpdate.value -Force
        }
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'GrantPermission' {
                Write-Information "Granting Intus-Inplanning entitlement: [$($actionContext.References.Permission.Reference)]"

                $body = ($correlatedAccount | ConvertTo-Json -Depth 10)
                $splatUpdateUserParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/users"
                    Headers     = $headers
                    Method      = 'PUT'
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = 'application/json;charset=utf-8'
                }
                $null = Invoke-RestMethod @splatUpdateUserParams -Verbose:$false
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Grant permission [$($actionContext.References.Permission.DisplayName)] was successful"
                        IsError = $false
                    })
            }

            'NotFound' {
                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Intus-Inplanning account: [$($actionContext.References.Account)] for person: [$($personContext.Person.DisplayName)] could not be found, possibly indicating that it could be deleted"
                        IsError = $true
                    })
                break
            }
        }
    }

} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Intus-InplanningError -ErrorObject $ex
        $auditMessage = "Could not grant Intus-Inplanning permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not grant Intus-Inplanning permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}