# Repair Network and DNS
# Fixes a host that cannot resolve or reach the AVD service, typically after a VPN client left its DNS servers or default route behind. Changes nothing when AVD is already reachable.
#Category: Agent Repair
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

# Locale-safe: every decision reads objects from the networking cmdlets (Get-NetRoute, Get-NetIPInterface,
# Get-DnsClientServerAddress, Resolve-DnsName) and socket results, never the text of a localized command's output.
# Safe for users: a host that cannot reach the AVD service has no working sessions, and nothing here logs anyone off.

$result = [ordered]@{
    success      = $false
    action       = 'none'
    changes      = @()
    endpoints    = [ordered]@{}
    dns_before   = @()
    dns_after    = @()
    nrpt_rules   = @()
    agent_restart = $false
}

# The broker the agent actually uses, plus the general AVD endpoints.
$endpoints = @('rdbroker.wvd.microsoft.com', 'rdweb.wvd.microsoft.com')
$brokerUri = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -Name 'BrokerURI').BrokerURI
if ($brokerUri) {
    $brokerHost = ([System.Uri]$brokerUri).Host
    if ($brokerHost -and ($endpoints -notcontains $brokerHost)) { $endpoints = @($brokerHost) + $endpoints }
}

function Test-Endpoint([string]$name) {
    $ip = (Resolve-DnsName -Name $name -Type A -DnsOnly -QuickTimeout | Where-Object { $_.IPAddress } | Select-Object -First 1).IPAddress
    if (-not $ip) { return [ordered]@{ resolves = $false; tcp443 = $false } }
    $ok = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $wait = $tcp.BeginConnect($name, 443, $null, $null)
        $ok = $wait.AsyncWaitHandle.WaitOne(4000) -and $tcp.Connected
        $tcp.Close()
    } catch { $ok = $false }
    return [ordered]@{ resolves = $true; ip = $ip; tcp443 = $ok }
}

function Test-AllEndpoints {
    $all = $true
    $map = [ordered]@{}
    foreach ($ep in $endpoints) {
        $t = Test-Endpoint $ep
        $map[$ep] = $t
        if (-not ($t.resolves -and $t.tcp443)) { $all = $false }
    }
    return @{ ok = $all; map = $map }
}

function Get-DnsView {
    @(Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } |
        ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ',')" })
}

$result.dns_before = Get-DnsView
$result.nrpt_rules = @(Get-DnsClientNrptPolicy | ForEach-Object { "$($_.Namespace) -> $($_.NameServers -join ',')" })

# 1. Already healthy: change nothing.
$check = Test-AllEndpoints
$result.endpoints = $check.map
if ($check.ok) {
    $result.success = $true
    $result.dns_after = $result.dns_before
    $result | ConvertTo-Json -Depth 4
    exit 0
}

# 2. Default routes left on an interface that is no longer connected (a VPN adapter that went down).
$connected = @{}
Get-NetIPInterface -AddressFamily IPv4 | ForEach-Object { $connected[$_.InterfaceIndex] = ($_.ConnectionState -eq 'Connected') }
foreach ($route in @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0')) {
    if (-not $connected[$route.InterfaceIndex]) {
        Remove-NetRoute -InputObject $route -Confirm:$false
        $result.changes += "removed default route on disconnected interface $($route.InterfaceAlias)"
    }
}

# 3. DNS on the connected interfaces that carry a default route: reset to the network's DNS (DHCP; in Azure, the
#    virtual network's DNS) when a server is a loopback address or none of the configured servers answers.
$defaultIfIndexes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object -ExpandProperty InterfaceIndex -Unique)
foreach ($idx in $defaultIfIndexes) {
    $entry = Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4
    $servers = @($entry.ServerAddresses)
    if ($servers.Count -eq 0) { continue }
    $loopback = @($servers | Where-Object { $_ -like '127.*' }).Count -gt 0
    $answers = $false
    foreach ($s in $servers) {
        if ($s -like '127.*') { continue }
        if (Resolve-DnsName -Name 'rdbroker.wvd.microsoft.com' -Server $s -Type A -DnsOnly -QuickTimeout) { $answers = $true; break }
    }
    if ($loopback -or -not $answers) {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses
        $result.changes += "reset DNS on $($entry.InterfaceAlias) to the network's servers (was $($servers -join ','))"
    }
}

if ($result.changes.Count -gt 0) {
    # Renew the DHCP lease so the network's DNS servers apply now (CIM method; no text to parse).
    Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = TRUE AND DHCPEnabled = TRUE' |
        ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName RenewDHCPLease | Out-Null }
    Start-Sleep -Seconds 3
}
Clear-DnsClientCache

# 4. Test again; when the service is reachable now, restart the agent so it reconnects without waiting.
$check = Test-AllEndpoints
$result.endpoints = $check.map
$result.dns_after = Get-DnsView
if ($result.changes.Count -gt 0) { $result.action = 'repaired' }
if ($check.ok) {
    if ($result.changes.Count -gt 0) {
        Restart-Service -Name 'RDAgentBootLoader' -Force
        $result.agent_restart = $true
    }
    $result.success = $true
    $result | ConvertTo-Json -Depth 4
    exit 0
}

$result.action = if ($result.changes.Count -gt 0) { 'repaired_still_unreachable' } else { 'nothing_to_repair_still_unreachable' }
$result | ConvertTo-Json -Depth 4
exit 1
