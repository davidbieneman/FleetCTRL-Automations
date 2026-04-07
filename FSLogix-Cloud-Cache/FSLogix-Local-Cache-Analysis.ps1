# FSLogix: Local Cache Analysis
# Inspects local Cloud Cache directory (C:\ProgramData\FSLogix\Cache) for per-user cache sizes, total consumption, free space on cache drive, and replication backlog (.queue/.index file counts).
#Category: FSLogix: Cloud Cache
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Cloud Cache Local Cache Analysis — inspect cache directory for size and health.
.NOTES
    FleetCTRL Script Library | Category: Cloud Cache
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$cachePath = Join-Path -Path $env:ProgramData -ChildPath 'FSLogix\Cache'
$proxyPath = Join-Path -Path $env:ProgramData -ChildPath 'FSLogix\Proxy'

$cacheEntries = [System.Collections.ArrayList]::new()
$totalCacheBytes = 0

if (Test-Path $cachePath) {
    $userDirs = Get-ChildItem -Path $cachePath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $userDirs) {
        $dirSize = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $queueFiles = (Get-ChildItem -Path $dir.FullName -Filter '*.queue' -File -ErrorAction SilentlyContinue).Count
        $indexFiles = (Get-ChildItem -Path $dir.FullName -Filter '*.index' -File -ErrorAction SilentlyContinue).Count
        $totalCacheBytes += $dirSize

        [void]$cacheEntries.Add(@{
            UserFolder   = $dir.Name
            SizeMB       = [math]::Round($dirSize / 1MB, 1)
            QueueFiles   = $queueFiles
            IndexFiles   = $indexFiles
            HasBacklog   = ($queueFiles -gt 0 -or $indexFiles -gt 5)
            LastWriteUtc = $dir.LastWriteTimeUtc.ToString('o')
        })
    }
}

# Cache drive free space
$cacheDrive = $env:SystemDrive
$disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$cacheDrive'" -ErrorAction SilentlyContinue
$driveInfo = if ($disk) {
    @{
        Drive       = $cacheDrive
        TotalGB     = [math]::Round($disk.Size / 1GB, 1)
        FreeGB      = [math]::Round($disk.FreeSpace / 1GB, 1)
        FreePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        CacheUsagePercent = if ($disk.Size -gt 0) { [math]::Round(($totalCacheBytes / $disk.Size) * 100, 2) } else { 0 }
    }
} else { $null }

$output = @{
    Timestamp     = [datetime]::UtcNow.ToString('o')
    ComputerName  = $env:COMPUTERNAME
    CachePath     = $cachePath
    CacheExists   = (Test-Path $cachePath)
    ProxyPath     = $proxyPath
    ProxyExists   = (Test-Path $proxyPath)
    Summary       = @{
        TotalCacheSizeMB = [math]::Round($totalCacheBytes / 1MB, 1)
        UserCaches       = $cacheEntries.Count
        BacklogUsers     = ($cacheEntries | Where-Object { $_.HasBacklog }).Count
    }
    DriveInfo     = $driveInfo
    CacheEntries  = $cacheEntries | Sort-Object -Property SizeMB -Descending
}

$output | ConvertTo-Json -Depth 3
