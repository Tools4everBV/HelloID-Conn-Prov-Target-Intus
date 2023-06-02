###################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Create
#
# Version: 1.0.1
###################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

function New-LastName {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    switch ($person.Name.Convention) {
        "B" {
            $surename = $person.Name.FamilyName
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix))) {
                $surename += ", " + $person.Name.FamilyNamePrefix
            }
        }
        "BP" { 
            $surename = $person.Name.FamilyName
            $surename += " - "
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix))) {
                $surename += $person.Name.FamilyNamePartnerPrefix + " "
            }
            $surename += $person.Name.FamilyNamePartner
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix))) {
                $surename += ", " + $person.Name.FamilyNamePrefix 
            }
        }
        "P" { 
            $surename = $person.Name.FamilyNamePartner 
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix))) {
                $surename += ", " + $person.Name.FamilyNamePartnerPrefix 
            }
        }
        "PB" { 
            $surename = $person.Name.FamilyNamePartner
            $surename += " - "
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix))) {
                $surename += $person.Name.FamilyNamePrefix + " "
            }
            $surename += $person.Name.FamilyName   
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix))) {
                $surename += ", " + $person.Name.FamilyNamePartnerPrefix 
            }
        }
        default {
            $surename = $person.Name.FamilyName
            if (-Not([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix))) {
                $surename += ", " + $person.Name.FamilyNamePrefix
            }
        }
    }

    Write-Output $surename
}

# Account mapping
$account = [PSCustomObject]@{
    username            = $p.Accounts.MicrosoftActiveDirectory.UserPrincipalName
    firstName           = $p.Name.GivenName
    lastName            = New-LastName -Person $p
    active              = $false
    email               = $p.Accounts.MicrosoftActiveDirectory.mail
    userGroup           = 'Root'
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $false

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

    if ([string]::IsNullOrEmpty($account.username)){
        throw "Username empty or not found"
    }

    try {
        $splatGetUserParams = @{
            Uri         = "$($config.BaseUrl)/api/users/$($account.UserName)"
            Headers     = $headers
            Method      = "GET"
        }
        $responseUser = Invoke-RestMethod @splatGetUserParams
    }
    catch {
        if(-not($_.ErrorDetails.Message -match "211 - Object does not exist")){            
            throw "Cannot get user error: [$($_.Exception.Message)]"
        }
    }
    
    # Verify if a user must be either [created and correlated], [updated and correlated] or just [correlated]
    if ($null -eq $responseUser){
        $action = 'Create-Correlate'
    } elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    } else {
        $action = 'Correlate'
    }

    # Add a warning message showing what will happen during enforcement
    if ($dryRun -eq $true) {
        Write-Warning "[DryRun] $action Intus account for: [$($p.DisplayName)], will be executed during enforcement"
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating Intus account'
                $splatNewUserParams = @{
                    Uri         = "$($config.BaseUrl)/api/users"
                    Headers     = $headers
                    Method      = "POST"
                    Body        = $account | ConvertTo-Json
                }
                $responseUser = Invoke-RestMethod @splatNewUserParams
                $accountReference = $account.UserName
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating Intus account'
                $splatSetUserParams = @{
                    Uri         = "$($config.BaseUrl)/api/users"
                    Headers     = $headers
                    Method      = "PUT"
                    Body        = $account | ConvertTo-Json
                }
                $responseUser = Invoke-RestMethod @splatSetUserParams
                $accountReference = $account.UserName
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating Intus account'
                $accountReference = $responseUser.UserName
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IntusError -ErrorObject $ex
        $auditMessage = "Could not $action Intus account. Error: $($errorObj.FriendlyMessage)"
        Write-Verbose "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not $action Intus account. Error: $($ex.Exception.Message)"
        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $auditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
# End
} finally {
    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
