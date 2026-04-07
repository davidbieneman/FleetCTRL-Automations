# FSLogix: Cloud Cache Status
# Uses Microsoft's native Microsoft.FSLogix module to get real-time Cloud Cache provider health: connection state, heartbeat latency, write queue depth, access mode, and uptime.
#Category: FSLogix: Cloud Cache
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Cloud Cache Provider Status — real-time health via Microsoft.FSLogix module.
.DESCRIPTION
    Uses Microsoft's native Microsoft.FSLogix module cmdlets to get live
    Cloud Cache provider health: connection state, heartbeat latency,
    write queue depth, access mode, and uptime. No admin rights required.
.NOTES
    FleetCTRL Script Library | Category: Cloud Cache
    Trigger: On-Demand / Boot | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$ccdLocations = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'CCDLocations' -ErrorAction SilentlyContinue).CCDLocations

if (-not $ccdLocations) {
    @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        CloudCacheEnabled = $false
        Message      = 'Cloud Cache is not configured (no CCDLocations)'
    } | ConvertTo-Json -Depth 2
    return
}

# Try to load the module
$moduleAvailable = $false
try {
    Import-Module -Name 'Microsoft.FSLogix' -ErrorAction Stop
    $moduleAvailable = $true
} catch {
    # Module not available
}

$providers = [System.Collections.ArrayList]::new()
$disks = [System.Collections.ArrayList]::new()

if ($moduleAvailable) {
    # Get Cloud Cache disks (proxy files)
    try {
        $ccdDisks = Get-CloudCacheDisk -ErrorAction Stop
        foreach ($disk in $ccdDisks) {
            [void]$disks.Add(@{
                Name       = $disk.Name
                Path       = $disk.Path
                Size       = $disk.Size
                State      = $disk.State.ToString()
                Type       = $disk.Type.ToString()
            })
        }
    } catch { }

    # Get Cloud Cache providers
    try {
        $ccdProviders = Get-CloudCacheProvider -ErrorAction Stop
        foreach ($prov in $ccdProviders) {
            # Extract heartbeat latency from LastLockOperation string
            $heartbeatMs = $null
            if ($prov.LastLockOperation -match '(\d+)\s*ms') {
                $heartbeatMs = [int]$Matches[1]
            }

            [void]$providers.Add(@{
                Name              = $prov.Name
                Type              = $prov.Type.ToString()
                Connected         = $prov.Connected
                State             = $prov.State.ToString()
                AccessMode        = $prov.AccessMode.ToString()
                RemotePath        = $prov.RemotePath
                LocalPath         = $prov.LocalPath
                Size              = $prov.Size
                SizeMB            = [math]::Round($prov.Size / 1MB, 1)
                WriteQueueLength  = $prov.WriteQueueLength
                Uptime            = if ($prov.Uptime) { $prov.Uptime.ToString() } else { $null }
                LastLockOperation = $prov.LastLockOperation
                HeartbeatMs       = $heartbeatMs
                Exists            = $prov.Exists
                IsHealthy         = ($prov.Connected -and $prov.State.ToString() -eq 'Valid' -and $prov.WriteQueueLength -eq 0)
            })
        }
    } catch { }
}

# Summary
$healthyCount = ($providers | Where-Object { $_.IsHealthy }).Count
$totalProviders = $providers.Count
$maxQueueDepth = ($providers | Measure-Object -Property WriteQueueLength -Maximum).Maximum

$output = @{
    Timestamp         = [datetime]::UtcNow.ToString('o')
    ComputerName      = $env:COMPUTERNAME
    CloudCacheEnabled = $true
    ModuleAvailable   = $moduleAvailable
    Summary           = @{
        TotalProviders  = $totalProviders
        HealthyProviders = $healthyCount
        UnhealthyProviders = $totalProviders - $healthyCount
        MaxWriteQueueDepth = $maxQueueDepth
        TotalDisks      = $disks.Count
    }
    Providers         = $providers
    Disks             = $disks
    CCDLocations      = $ccdLocations
}

$output | ConvertTo-Json -Depth 3
