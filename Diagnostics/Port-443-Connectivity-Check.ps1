# Port 443 Connectivity Check
# Tests TCP 443 connectivity to AVD broker endpoints. If blocked, agent cannot register or maintain heartbeat (Event 3703).
#Category: Diagnostics
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$endpoints = @(
    'rdbroker.wvd.microsoft.com',
    'rdweb.wvd.microsoft.com',
    'rddiagnostics.wvd.microsoft.com'
)
$results = @{}
$allOk = $true
foreach ($ep in $endpoints) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($ep, 443)
        $results[$ep] = 'reachable'
        $tcp.Close()
    } catch {
        $results[$ep] = "blocked: $($_.Exception.Message)"
        $allOk = $false
    }
}
@{ success = $allOk; endpoints = $results } | ConvertTo-Json -Depth 3