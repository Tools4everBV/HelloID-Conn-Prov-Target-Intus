######################################################
# HelloID-Conn-Prov-Target-Intus-Inplanning-Permissions
# PowerShell V2
######################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Information 'Retrieving permissions'
    # <Paste your Json Permissions here> (More information can be found in the Readme)
    $jsonPermissions = @'
    [
        {
            "role": "Planner",
            "resourceGroup": "Planner {{LocationOwn}}",
            "exchangeGroup": "Company",
            "shiftGroup": "Company",
            "worklocationGroup": "Root",
            "userGroup": "Root"
        },
        {
            "role": "Leidinggevende",
            "resourceGroup": "{{costcenterOwn}}",
            "exchangeGroup": "Company",
            "shiftGroup": "Company",
            "worklocationGroup": "Root",
            "userGroup": "Root"
        },
        {
            "role": "ADMIN",
            "resourceGroup": "ADMIN",
            "exchangeGroup": "ADMIN",
            "shiftGroup": "ADMIN",
            "worklocationGroup": "Root",
            "userGroup": "Root"
        }
    ]
'@

    $permissionList = $jsonPermissions | ConvertFrom-Json
    foreach ($permission in $permissionList) {
        $outputContext.Permissions.Add(@{
                DisplayName    = $permission.PSObject.Properties.Name
                Identification = @{
                    Reference   = $permission."$($permission.PSObject.Properties.Name)"
                    DisplayName = $permission.PSObject.Properties.Name
                }
            })
    }
}
catch {
    $ex = $PSItem
    Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
}
