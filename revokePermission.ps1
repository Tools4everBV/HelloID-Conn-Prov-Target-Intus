################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-RevokePermissionDynamic
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
    $currentpermissions = $actionContext.CurrentPermissions
    
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
        $currentRoles = $correlatedAccount.roles.psobject.copy()
        $process = $true
    }
    else {
        $process = $false
    }

    # Sub-permissions
    $newRoles = [System.Collections.Generic.List[PSCustomObject]]::new()
    if ($null -ne $currentRoles) {
        $newRoles = $currentRoles.psobject.copy()
    }
    $action = "nochanges"
    foreach ($permission in $currentpermissions.reference) {
        Write-verbose "revoking: $($permission.role) : $($permission.resourceGroup)"

        $existingRole = $currentRoles.Where({ $_.role -eq $permission.role -AND $_.resourceGroup -eq $permission.resourceGroup })
        if ($existingRole.count -gt 1) {
            throw "Multiple roles with the same name found [$($permission.role)]"
        }
        elseif ($existingRole.count -eq 1) {
            $newRoles = @($newRoles | Where-Object { -NOT ($_.role -eq $permission.role -AND $_.resourceGroup -eq $permission.resourceGroup) })
            $action = "RevokePermission"
        }
    }

if($process){
    #UPDATE USER
    switch ($action) {
        'RevokePermission' {
            $newRoles = $newRoles | Select-Object -Property * -ExcludeProperty "SideIndicator"
            $correlatedAccount.roles = @($newRoles)

            $body = ($correlatedAccount | ConvertTo-Json -Depth 10)

            Write-Warning "body $body"

            $splatUpdateUserParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/api/users"
                Headers     = $headers
                Method      = 'PUT'
                Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                ContentType = 'application/json;charset=utf-8'
            }
            if (-not($actionContext.DryRun -eq $true)) {
                $null = Invoke-RestMethod @splatUpdateUserParams -Verbose:$false
            }
            else {
                Write-Warning "[DRYRUN] will set roles: $($correlatedAccount.roles | convertto-json)"
            }


            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "revoke permission [$($actionContext.References.Permission.DisplayName)] was successful"
                    IsError = $false
                })
        }
        'NoChanges' {
            Write-verbose "Nothing to change - returning subpermissions $($outputContext.SubPermissions.displayname -join("|"))"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Revoking permission [$($actionContext.References.Permission.DisplayName)] skipped - NoChanges"
                    IsError = $false
                })
        }

    }
    $outputContext.Success = $true
}else{
        $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Intus-Inplanning account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted - revoke was successful"
                    IsError = $false
                })

}
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Intus-InplanningError -ErrorObject $ex
        $auditMessage = "Could not revoke Intus-Inplanning permission. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not revoke Intus-Inplanning permission. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}


