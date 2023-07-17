
#######################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Permissions
#
# Version: 1.1.0
#######################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

try {
    $jsonPermissions = @'
        <Paste your Json Permissions here> (More information can be found in the Readme)
'@

    $jsonPermissions = $jsonPermissions | ConvertFrom-Json
    $permissionList = [System.Collections.Generic.List[object]]::new()

    foreach ($permission in $jsonPermissions) {
        $permissionList.Add(
            [pscustomobject]@{
                DisplayName = $permission.psobject.Properties.name
                Identification = [pscustomobject]@{
                    Reference = $permission."$($permission.psobject.Properties.name)"
                    DisplayName = $permission.psobject.Properties.name
                }
            }
        )
    }

    Write-Output $permissionList | ConvertTo-Json -Depth 10
}
catch {
    $ex = $PSItem
    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
}