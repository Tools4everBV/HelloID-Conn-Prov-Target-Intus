###############################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Entitlement-Grant
#
# Version: 1.1.0
###############################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Is only used when there is a variable in the permissions {{costCenterOwn}}
$account = [PSCustomObject]@{
    costCenter = $p.PrimaryContract.CostCenter.name
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Region functions
function Get-AccessToken {
    [CmdletBinding()]
    param (
    )
    process {
        try {
            $tokenHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
            $tokenHeaders.Add("Content-Type", "application/x-www-form-urlencoded")

            $splatGetTokenParams = @{
                Uri     = "$($config.BaseUrl)/api/token"
                Headers = $tokenHeaders
                Method  = "POST"
                Body    = @{
                    client_id     = $config.clientId
                    client_secret = $config.clientSecret
                    grant_type    = "client_credentials"
                }
            }
            write-output (Invoke-RestMethod @splatGetTokenParams).access_token
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }   
    }
}

function Resolve-IntusError {
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
            # Displaying the old message if an error occurs during an API call, as the error is related to the API call and not the conversion process to JSON.
        }
        Write-Output $httpErrorObj
    }
}
# Endregion

try {
    $accessToken = Get-AccessToken
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Content-Type", "application/json")
    $headers.Add('Authorization', 'Bearer ' + $accessToken)
    
    if ([string]::IsNullOrEmpty($aRef)) {
        throw "No account Reference found"
    }

    # Verify if a user account exists in the target system
    # Make sure to fail the action if the account does not exist in the target system!
    try {
        $splatGetUserParams = @{
            Uri     = "$($config.BaseUrl)/api/users/$($aRef)"
            Headers = $headers
            Method  = "GET"
        }
        $responseUser = Invoke-RestMethod @splatGetUserParams -Verbose:$false
    }
    catch {
        if (-not($_.ErrorDetails.Message -match "211 - Object does not exist")) {  
            throw "Cannot get user error: [$($_.Exception.Message)] [$($_.ErrorDetails.Message)]"
        }
    }

    # Add a informational message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Information "[DryRun] Grant Intus-Inplanning entitlement: [$($pRef.DisplayName)] to: [$($p.DisplayName)] will be executed during enforcement"
    }

    # Replacing placeholders in the permission with the value's from HelloId contract
    foreach ($property in $pRef.Reference.psobject.Properties) {
        if ($property.value -eq "{{costCenterOwn}}") {
            if ([string]::IsNullOrEmpty($account.costCenter)) {
                throw "Permission expects [{{costCenterOwn}}] to grant the permission the specified cost center is empty"
            }
            $pref.Reference."$($property.name)" = $account.costCenter
            Write-Verbose "Replacing property: [$($property.name)] value: [{{costCenterOwn}}] with [$($account.costCenter)]"
        }
    }  
    
    # Add or update user with role
    $existingRole = $responseUser.roles.Where({ $_.role -eq $pref.Reference.role })
    if ($existingRole.count -gt 1) {
        throw "Multiple roles with the same name found [$($pRef.Reference.role)]"
    }
    elseif ($existingRole.count -eq 0) {
        $startDate = Get-Date -Format "yyyy-MM-dd"
        $pRef.Reference | Add-Member -MemberType NoteProperty -Name 'startDate' -Value $startDate
        $responseUser.roles += $pref.Reference
    }
    else {
        # Possibly implement a comparison to verify whether an update is necessary instead of always performing an update.
        $existingRole | Add-Member -MemberType NoteProperty -Name 'endDate' -Value $null -Force
        foreach ($propertiesToUpdate in $pRef.Reference.psobject.Properties) {
            $existingRole | Add-Member -MemberType NoteProperty -Name "$($propertiesToUpdate.name)" -Value $propertiesToUpdate.value -Force

        }
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Granting Intus-Inplanning entitlement: [$($pRef.DisplayName)]"
        $body = ($responseUser | ConvertTo-Json -Depth 10)
        $splatUpdateUserParams = @{
            Uri         = "$($config.BaseUrl)/api/users"
            Headers     = $headers
            Method      = "PUT"
            Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
            ContentType = "application/json;charset=utf-8"
        } 
        $responseUser = Invoke-RestMethod @splatUpdateUserParams -Verbose:$false
    }
    $success = $true
    $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Intus-Inplanning entitlement: [$($pRef.DisplayName)] was successful"
            IsError = $false
        })
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IntusError -ErrorObject $ex
        $auditMessage = "Could not grant Intus-Inplanning entitlement: [$($pRef.DisplayName)]. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditMessage = "Could not grant Intus-Inplanning entitlement: [$($pRef.DisplayName)]. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}