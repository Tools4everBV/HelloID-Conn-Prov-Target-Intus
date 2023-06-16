###################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Enable
#
# Version: 1.1.0
###################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Get-AccessToken {
    [CmdletBinding()]
    param (
    )
    process {
        try {
            $tokenHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
            $tokenHeaders.Add("Content-Type", "application/x-www-form-urlencoded")

            $splatGetTokenParams = @{
                Uri         = "$($config.BaseUrl)/api/token"
                Headers     = $tokenHeaders
                Method      = "POST"
                Body        =  @{
                    client_id       = $config.clientId
                    client_secret   = $config.clientSecret
                    grant_type      = "client_credentials"
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
        elseif((-not($null -eq $ErrorObject.Exception.Response) -and $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException')) {         
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
    $accessToken = Get-AccessToken
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Content-Type", "application/json")
    $headers.Add('Authorization', 'Bearer ' + $accessToken)

    Write-Verbose "Verifying if a Intus account for [$($p.DisplayName)] exists"
    # Make sure to fail the action if the account does not exist in the target system!
    
    if ([string]::IsNullOrEmpty($aRef)){
        throw "No account Reference found"
    }

    try {
        $splatGetUserParams = @{
            Uri         = "$($config.BaseUrl)/api/users/$($aRef)"
            Headers     = $headers
            Method      = "GET"
        }
        $responseUser = Invoke-RestMethod @splatGetUserParams
    }
    catch {
        if(-not($_.ErrorDetails.Message -match "211 - Object does not exist")){      
            $action = 'NotFound'      
            throw "Cannot get user error: [$($_.Exception.Message)]"
        }
    }
    if ($responseUser){
        $action = 'Found'
        $dryRunMessage = "Enabling Intus account for: [$($p.DisplayName)] will be executed during enforcement"
    } elseif($null -eq $responseUser) {
        $action = 'NotFound'
        $dryRunMessage = "Intus account for: [$($p.DisplayName)] not found. Possibly deleted."
    }
    
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $dryRunMessage"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action){
            'Found' {
                Write-Verbose "Enabling Intus account with accountReference: [$aRef]"
                $responseUser.active = $true

                $body = ($responseUser | ConvertTo-Json -Depth 10)
                $splatUpdateUserParams = @{
                    Uri         = "$($config.BaseUrl)/api/users"
                    Headers     = $headers
                    Method      = "PUT"
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = "application/json;charset=utf-8"
                } 
                $responseUser = Invoke-RestMethod @splatUpdateUserParams
                
                $success = $true
                $auditLogs.Add([PSCustomObject]@{
                    Message = 'Enable account was successful'
                    IsError = $false
                })
                break
            }
            'NotFound' {
                $success = $false
                $auditLogs.Add([PSCustomObject]@{
                    Message = "Intus account for: [$($p.DisplayName)] not found. Could not enable account"
                    IsError = $true
                })
                break
            }
        }
    }            
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IntusError -ErrorObject $ex
        $auditMessage = "Could not enable Intus account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not enable Intus account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}