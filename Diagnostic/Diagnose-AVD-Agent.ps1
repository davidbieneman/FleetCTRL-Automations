# Diagnose AVD Agent
# Reads full agent state and returns JSON diagnosis with recommended fix script. Always run this first.
#Category: Diagnostic
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$diag = @{}

# Service status
foreach ($sn in @('RDAgentBootLoader','RdAgent')) {
    $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
    $diag[$sn] = @{
        exists     = ($null -ne $svc)
        status     = if ($svc) { $svc.Status.ToString() } else { 'not_found' }
        start_type = if ($svc) { $svc.StartType.ToString() } else { 'n/a' }
    }
}

# RDInfraAgent registry
$rdPath = 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
if (Test-Path $rdPath) {
    $props = Get-ItemProperty -Path $rdPath
    $diag['RDInfraAgent'] = @{
        exists              = $true
        IsRegistered        = $props.IsRegistered
        has_token           = (-not [string]::IsNullOrEmpty($props.RegistrationToken))
        BrokerURI           = $props.BrokerURI
        AgentVersion        = $props.AgentVersion
    }
} else { $diag['RDInfraAgent'] = @{ exists = $false } }

# BootLoader registry
$blPath = 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader'
$diag['RDAgentBootLoader_reg'] = @{ exists = (Test-Path $blPath) }

# Event log errors (last 10)
$diag['recent_errors'] = @(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='RDAgent','RDAgentBootLoader';Level=2} -MaxEvents 10 -ErrorAction SilentlyContinue | ForEach-Object { @{ time = $_.TimeCreated.ToString('o'); id = $_.Id; msg = $_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)) } })

# Disk space
$c = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DeviceID="C:"'
$diag['disk'] = @{ free_gb = [math]::Round($c.FreeSpace / 1GB, 1); total_gb = [math]::Round($c.Size / 1GB, 1) }

# .NET version
$dotnet = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
$diag['dotnet_release'] = $dotnet
$diag['dotnet_ok'] = ($dotnet -ge 461808)

# Port 443 to broker
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect('rdbroker.wvd.microsoft.com', 443)
    $diag['port_443'] = 'reachable'
    $tcp.Close()
} catch { $diag['port_443'] = 'blocked' }

# SxS listener
$qwinsta = & qwinsta 2>$null
$sxs = $qwinsta | Where-Object { $_ -match 'rdp-sxs' }
$diag['rdp_sxs'] = if ($sxs) { 'present' } else { 'missing' }

# Tombstone
$tomb = Join-Path $env:ProgramData 'FleetCTRL\PRECAPTURE_CLEANUP_COMPLETE'
$diag['precapture_tombstone'] = (Test-Path $tomb)

# Recommendation
$rec = 'none'
if (-not $diag['RDInfraAgent'].exists) { $rec = 'fix_install_missing_agent' }
elseif ($diag.RDAgentBootLoader.status -eq 'not_found') { $rec = 'fix_reinstall_agent' }
elseif ($diag.RDAgentBootLoader.status -ne 'Running' -or $diag.RdAgent.status -ne 'Running') { $rec = 'fix_restart_services' }
elseif ($diag['RDInfraAgent'].IsRegistered -ne 1) { $rec = 'fix_reregister_token' }
elseif ($diag.rdp_sxs -eq 'missing') { $rec = 'fix_sxs_stack' }
elseif ($diag.disk.free_gb -lt 2) { $rec = 'fix_disk_cleanup' }
elseif (-not $diag.dotnet_ok) { $rec = 'fix_dotnet_check' }
elseif ($diag.port_443 -eq 'blocked') { $rec = 'fix_port_443_check' }
$diag['recommended_script'] = $rec

$diag | ConvertTo-Json -Depth 3