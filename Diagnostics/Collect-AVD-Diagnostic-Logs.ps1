# Collect AVD Diagnostic Logs
# Gathers AVD agent logs, event log entries, and service state into a single JSON bundle for support troubleshooting.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$logs = @{}

$logs['services'] = @{}
foreach ($sn in @('RDAgentBootLoader','RdAgent','frxsvc','TermService')) {
    $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
    $logs.services[$sn] = if ($svc) { $svc.Status.ToString() } else { 'not_found' }
}

$logs['events'] = @(Get-WinEvent -FilterHashtable @{LogName='Application';ProviderName='RDAgent','RDAgentBootLoader';Level=1,2,3} -MaxEvents 50 -ErrorAction SilentlyContinue | ForEach-Object {
    @{ time = $_.TimeCreated.ToString('o'); level = $_.LevelDisplayName; id = $_.Id; msg = $_.Message.Substring(0, [Math]::Min(500, $_.Message.Length)) }
})

$agentLogDir = Join-Path $env:ProgramFiles 'Microsoft RDInfra'
$latestLog = Get-ChildItem -Path $agentLogDir -Filter '*.log' -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestLog) {
    $logs['agent_log_file'] = $latestLog.FullName
    $logs['agent_log_tail'] = (Get-Content $latestLog.FullName -Tail 200 -ErrorAction SilentlyContinue) -join "`n"
}

$rdPath = 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
if (Test-Path $rdPath) {
    $props = Get-ItemProperty -Path $rdPath
    $logs['registry'] = @{
        IsRegistered = $props.IsRegistered
        AgentVersion = $props.AgentVersion
        BrokerURI    = $props.BrokerURI
    }
}

$c = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DeviceID="C:"'
$logs['disk_free_gb'] = [math]::Round($c.FreeSpace / 1GB, 1)

$logs['collected_at'] = (Get-Date -Format 'o')
@{ success = $true; data = $logs } | ConvertTo-Json -Depth 4