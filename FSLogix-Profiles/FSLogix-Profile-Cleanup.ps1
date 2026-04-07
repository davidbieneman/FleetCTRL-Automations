# FSLogix: Profile Cleanup
# Removes bloat data (browser caches, Teams cache, temp files, crash dumps) from inside profile containers based on configurable age thresholds. Adapted from Aaron Parker's targets (MIT).
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 300
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Profile Container Cleanup — remove bloat data from user profiles.
.DESCRIPTION
    Deletes browser caches, Teams cache, temp files, crash dumps from user profiles
    based on configurable age thresholds. Cleanup targets adapted from Aaron Parker (MIT).
    Runs against local user profiles, not mounted VHDs (use for persistent session hosts).
.NOTES
    FleetCTRL Script Library | Category: Profile Container
    Trigger: On-Demand | Admin Required: Yes | Destructive: Yes
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$WhatIf_Mode,
    [string]$TargetUser = '*'
)

$ErrorActionPreference = 'SilentlyContinue'
if ($WhatIf_Mode) { $WhatIfPreference = $true }

# Cleanup target definitions (from Aaron Parker's targets.xml, MIT license)
$targets = @(
    # Windows system
    @{ Path = 'AppData\Local\Temp'; Action = 'Delete'; Desc = 'Windows Temp' }
    @{ Path = 'AppData\Local\CrashDumps'; Action = 'Delete'; Desc = 'Crash Dumps' }
    @{ Path = 'AppData\Local\Microsoft\Windows\WER'; Action = 'Delete'; Desc = 'Windows Error Reporting' }
    @{ Path = 'AppData\Local\D3DSCache'; Action = 'Delete'; Desc = 'D3D Shader Cache' }
    @{ Path = 'AppData\Local\Microsoft\Windows\GameExplorer'; Action = 'Delete'; Desc = 'Game Explorer' }
    @{ Path = 'AppData\Local\Package Cache'; Action = 'Delete'; Desc = 'Package Cache' }
    @{ Path = 'Downloads'; Action = 'Prune'; Days = 10; Desc = 'Downloads > 10 days' }
    
    # Browser caches
    @{ Path = 'AppData\Local\Google\Chrome\User Data\Default\Cache'; Action = 'Prune'; Days = 30; Desc = 'Chrome Cache' }
    @{ Path = 'AppData\Local\Google\Chrome\User Data\Default\Code Cache'; Action = 'Prune'; Days = 30; Desc = 'Chrome Code Cache' }
    @{ Path = 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'; Action = 'Prune'; Days = 30; Desc = 'Edge Cache' }
    @{ Path = 'AppData\Local\Microsoft\Edge\User Data\Default\Code Cache'; Action = 'Prune'; Days = 30; Desc = 'Edge Code Cache' }
    @{ Path = 'AppData\Local\Mozilla\Firefox\Profiles\*\cache2'; Action = 'Prune'; Days = 7; Desc = 'Firefox Cache' }
    
    # Teams Classic
    @{ Path = 'AppData\Roaming\Microsoft\Teams\Cache'; Action = 'Prune'; Days = 30; Desc = 'Teams Classic Cache' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\GPUCache'; Action = 'Prune'; Days = 30; Desc = 'Teams Classic GPU Cache' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\Service Worker'; Action = 'Prune'; Days = 1; Desc = 'Teams Classic Service Worker' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\media-stack'; Action = 'Prune'; Days = 1; Desc = 'Teams Classic Media Stack' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\logs'; Action = 'Prune'; Days = 1; Desc = 'Teams Classic Logs' }
    
    # New Teams
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs'; Action = 'Prune'; Days = 1; Desc = 'New Teams Logs' }
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\PerfLogs'; Action = 'Prune'; Days = 1; Desc = 'New Teams Perf Logs' }
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\GPUCache'; Action = 'Delete'; Desc = 'New Teams GPU Cache' }
    
    # New Outlook
    @{ Path = 'AppData\Local\Microsoft\olk\logs'; Action = 'Prune'; Days = 1; Desc = 'New Outlook Logs' }
    @{ Path = 'AppData\Local\Microsoft\olk\EbWebView\default\WebStorage'; Action = 'Delete'; Desc = 'New Outlook WebStorage' }
    
    # Office
    @{ Path = 'AppData\Roaming\Microsoft\Word\*.tmp'; Action = 'Prune'; Days = 7; Desc = 'Word Temp Files' }
    @{ Path = 'AppData\Local\Microsoft\Office\16.0\Lync\Tracing'; Action = 'Prune'; Days = 7; Desc = 'Lync Tracing' }
    
    # OneDrive
    @{ Path = 'AppData\Local\Microsoft\OneDrive\logs'; Action = 'Prune'; Days = 7; Desc = 'OneDrive Logs' }
    
    # VS Code
    @{ Path = 'AppData\Roaming\Code\logs'; Action = 'Prune'; Days = 7; Desc = 'VS Code Logs' }
    @{ Path = 'AppData\Roaming\Code\Cache'; Action = 'Prune'; Days = 30; Desc = 'VS Code Cache' }
    
    # Slack
    @{ Path = 'AppData\Roaming\Slack\Cache'; Action = 'Prune'; Days = 30; Desc = 'Slack Cache' }
    @{ Path = 'AppData\Roaming\Slack\logs'; Action = 'Prune'; Days = 7; Desc = 'Slack Logs' }
    
    # Spotify
    @{ Path = 'AppData\Local\Spotify\Browser\Cache'; Action = 'Prune'; Days = 10; Desc = 'Spotify Cache' }
    @{ Path = 'AppData\Local\Spotify\Storage'; Action = 'Prune'; Days = 10; Desc = 'Spotify Storage' }
    
    # Misc
    @{ Path = 'AppData\Local\SquirrelTemp'; Action = 'Prune'; Days = 7; Desc = 'Electron Update Temp' }
    @{ Path = 'AppData\Local\Microsoft\CLR_v4.0'; Action = 'Prune'; Days = 7; Desc = '.NET CLR Cache' }
    @{ Path = 'AppData\Local\Microsoft\TokenBroker\Cache'; Action = 'Prune'; Days = 7; Desc = 'Token Broker Cache' }
)

# Find user profiles
$usersRoot = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
$userDirs = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

if ($TargetUser -ne '*') {
    $userDirs = $userDirs | Where-Object { $_.Name -eq $TargetUser }
}

$report = [System.Collections.ArrayList]::new()
$totalBytesFreed = 0
$totalFilesRemoved = 0

foreach ($userDir in $userDirs) {
    $userBytesFreed = 0
    $userFilesRemoved = 0
    
    foreach ($target in $targets) {
        $fullPath = Join-Path -Path $userDir.FullName -ChildPath $target.Path
        
        if (-not (Test-Path -Path $fullPath -ErrorAction SilentlyContinue)) { continue }
        
        $files = @()
        switch ($target.Action) {
            'Delete' {
                $files = Get-ChildItem -Path $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue
            }
            'Prune' {
                $cutoff = [datetime]::UtcNow.AddDays(-$target.Days)
                $files = Get-ChildItem -Path $fullPath -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTimeUtc -lt $cutoff }
            }
        }
        
        if ($files.Count -gt 0) {
            $sizeBytes = ($files | Measure-Object -Property Length -Sum).Sum
            
            foreach ($file in $files) {
                if ($PSCmdlet.ShouldProcess($file.FullName, $target.Action)) {
                    try {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        $userFilesRemoved++
                        $userBytesFreed += $file.Length
                    } catch { }
                }
            }
            
            [void]$report.Add(@{
                User       = $userDir.Name
                Target     = $target.Desc
                Action     = $target.Action
                Path       = $target.Path
                FilesFound = $files.Count
                SizeMB     = [math]::Round($sizeBytes / 1MB, 1)
            })
        }
    }
    
    $totalBytesFreed += $userBytesFreed
    $totalFilesRemoved += $userFilesRemoved
}

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    WhatIfMode   = [bool]$WhatIf_Mode
    Summary      = @{
        UsersProcessed = $userDirs.Count
        TotalFilesRemoved = $totalFilesRemoved
        TotalSpaceFreedMB = [math]::Round($totalBytesFreed / 1MB, 1)
        TargetsChecked = $targets.Count
    }
    Details      = $report
}

$output | ConvertTo-Json -Depth 3
