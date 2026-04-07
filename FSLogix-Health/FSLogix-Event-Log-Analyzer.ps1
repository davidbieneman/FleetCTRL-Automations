# FSLogix: Event Log Analyzer
# Pulls FSLogix-specific Windows events (Apps, CloudCache logs) with severity classification, key Event ID documentation, and per-user grouping. Configurable time range.
#Category: FSLogix: Health
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    FSLogix Event Log Analyzer — pull and classify FSLogix events.
.DESCRIPTION
    Queries FSLogix-specific Windows Event logs with severity classification,
    key Event ID documentation, and per-user grouping.
.NOTES
    FleetCTRL Script Library | Category: Health & Diagnostics
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param(
    [int]$HoursBack = 24,
    [int]$MaxEvents = 200
)

$ErrorActionPreference = 'SilentlyContinue'

# Known FSLogix Event IDs with documentation
$knownEvents = @{
    25  = @{ Severity = 'Info';    Desc = 'Profile container attached successfully' }
    26  = @{ Severity = 'Info';    Desc = 'Profile loaded successfully' }
    57  = @{ Severity = 'Info';    Desc = 'Session connected to profile container' }
    9   = @{ Severity = 'Error';   Desc = 'VHD mount operation failed' }
    14  = @{ Severity = 'Warning'; Desc = 'Profile container size limit reached' }
    19  = @{ Severity = 'Error';   Desc = 'Network path unreachable' }
    23  = @{ Severity = 'Error';   Desc = 'Concurrent access limit exceeded' }
    56  = @{ Severity = 'Info';    Desc = 'Cloud Cache providers online status' }
    5   = @{ Severity = 'Info';    Desc = 'Cloud Cache proxy file lock acquired' }
    1   = @{ Severity = 'Info';    Desc = 'FSLogix service started' }
    2   = @{ Severity = 'Info';    Desc = 'FSLogix service stopped' }
    4   = @{ Severity = 'Error';   Desc = 'Profile container creation failed' }
    7   = @{ Severity = 'Error';   Desc = 'Container attach failed — file locked' }
    33  = @{ Severity = 'Warning'; Desc = 'Profile compaction skipped' }
    69  = @{ Severity = 'Info';    Desc = 'ODFC container attached' }
}

$cutoff = [datetime]::UtcNow.AddHours(-$HoursBack)
$events = [System.Collections.ArrayList]::new()

$logNames = @(
    'Microsoft-FSLogix-Apps/Operational',
    'Microsoft-FSLogix-Apps/Admin',
    'Microsoft-FSLogix-CloudCache/Operational'
)

foreach ($logName in $logNames) {
    try {
        $logEvents = Get-WinEvent -LogName $logName -MaxEvents $MaxEvents -ErrorAction Stop |
            Where-Object { $_.TimeCreated.ToUniversalTime() -ge $cutoff }
        
        foreach ($evt in $logEvents) {
            $known = $knownEvents[$evt.Id]
            [void]$events.Add(@{
                TimeCreatedUtc = $evt.TimeCreated.ToUniversalTime().ToString('o')
                LogName        = $logName
                EventId        = $evt.Id
                Level          = $evt.LevelDisplayName
                LevelValue     = $evt.Level  # 1=Critical, 2=Error, 3=Warning, 4=Info
                Message        = $evt.Message
                KnownEventDesc = if ($known) { $known.Desc } else { $null }
                KnownSeverity  = if ($known) { $known.Severity } else { $null }
                UserId         = if ($evt.UserId) { $evt.UserId.Value } else { $null }
            })
        }
    } catch {
        # Log may not exist if Cloud Cache not configured
    }
}

# Summary by severity
$errorCount = ($events | Where-Object { $_.LevelValue -le 2 }).Count
$warnCount = ($events | Where-Object { $_.LevelValue -eq 3 }).Count
$infoCount = ($events | Where-Object { $_.LevelValue -ge 4 }).Count

# Top Event IDs
$topEvents = $events | Group-Object -Property EventId |
    Sort-Object -Property Count -Descending |
    Select-Object -First 10 |
    ForEach-Object {
        $known = $knownEvents[[int]$_.Name]
        @{
            EventId     = [int]$_.Name
            Count       = $_.Count
            Description = if ($known) { $known.Desc } else { 'Unknown' }
        }
    }

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    HoursBack    = $HoursBack
    Summary      = @{
        TotalEvents = $events.Count
        Errors      = $errorCount
        Warnings    = $warnCount
        Info        = $infoCount
    }
    TopEventIds  = $topEvents
    Events       = $events | Sort-Object -Property TimeCreatedUtc -Descending
}

$output | ConvertTo-Json -Depth 4
