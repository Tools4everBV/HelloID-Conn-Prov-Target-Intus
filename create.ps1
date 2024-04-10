#################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Create
# PowerShell V2
#################################################

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

try {
    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Verify if a user must be either [created ] or just [correlated]
        $accessToken = Get-AccessToken
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Content-Type', 'application/json')
        $headers.Add('Authorization', 'Bearer ' + $accessToken)

        try {
            $splatGetUserParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/users/$correlationValue"
                Headers = $headers
                Method  = 'GET'
            }
            $correlatedAccount = Invoke-RestMethod @splatGetUserParams
        } catch {
            if (-not($_.ErrorDetails.Message -match '211 - Object does not exist')) {
                throw "Cannot get user error: [$($_.Exception.Message)]"
            }
        }
    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $action Intus-Inplanning account for: [$($personContext.Person.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($actionContext.DryRun -eq $true)) {
        switch ($action) {
            'CreateAccount' {
                Write-Information 'Creating and correlating Intus-Inplanning account'
                $body = ($actionContext.Data | ConvertTo-Json -Depth 10)
                $splatNewUserParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/users"
                    Headers     = $headers
                    Method      = 'POST'
                    Body        = ([System.Text.Encoding]::UTF8.GetBytes($body))
                    ContentType = 'application/json;charset=utf-8'
                }
                $createdAccount = Invoke-RestMethod @splatNewUserParams
                $outputContext.Data = $createdAccount
                $outputContext.AccountReference = $correlationValue
                $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)"
                break
            }

            'CorrelateAccount' {
                Write-Information 'Correlating Intus-Inplanning account'
                $outputContext.Data = $correlatedAccount
                $outputContext.AccountReference = $correlatedAccount.UserName
                $outputContext.AccountCorrelated = $true
                $auditLogMessage = "Correlated account: [$($correlatedAccount.UserName)] on field: [$($correlationField)] with value: [$($correlationValue)]"
                break
            }
        }
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = $action
                Message = $auditLogMessage
                IsError = $false
            })
    }
    $outputContext.success = $true
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Intus-InplanningError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Intus-Inplanning account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Intus-Inplanning account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
