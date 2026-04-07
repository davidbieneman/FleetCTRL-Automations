# FSLogix: VHD Compact
# Compacts dynamic VHD/VHDX files to reclaim unused white space. Checks mount status before compacting. Requires Hyper-V PowerShell module. Reports space saved per container.
#Category: FSLogix: Remediation
#Run On: on_demand
#Timeout: 600
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    VHD Compact — reclaim white space from dynamic VHD/VHDX files.
.NOTES
    FleetCTRL Script Library | Category: Remediation & Repair
    Trigger: On-Demand | Admin Required: Yes | Destructive: No
#>
[CmdletBinding()]
param(
    [string]$TargetPath = '',
    [int]$MaxContainers = 10
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not (Get-Module -ListAvailable -Name 'Hyper-V')) {
    @{ Timestamp = [datetime]::UtcNow.ToString('o'); ComputerName = $env:COMPUTERNAME; Error = 'Hyper-V PowerShell module not available' } | ConvertTo-Json
    return
}

$paths = @()
if ($TargetPath) {
    $paths = @($TargetPath)
} else {
    $profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
    if ($profReg.VHDLocations) { $paths = @($profReg.VHDLocations) | ForEach-Object { $_.Trim() } }
}

$results = [System.Collections.ArrayList]::new()
$totalSaved = 0

foreach ($path in $paths) {
    if (-not (Test-Path $path)) { continue }
    $vhdFiles = Get-ChildItem -Path $path -Recurse -Include '*.vhd','*.vhdx' -File -ErrorAction SilentlyContinue |
        Select-Object -First $MaxContainers

    foreach ($vhd in $vhdFiles) {
        $entry = @{ File = $vhd.FullName; SizeBeforeMB = [math]::Round($vhd.Length / 1MB, 1) }
        
        try {
            $vhdInfo = Get-VHD -Path $vhd.FullName -ErrorAction Stop
            if ($vhdInfo.Attached) {
                $entry['Status'] = 'Skipped'
                $entry['Message'] = 'VHD is currently attached/mounted'
                [void]$results.Add($entry)
                continue
            }
            if ($vhdInfo.VhdType.ToString() -ne 'Dynamic') {
                $entry['Status'] = 'Skipped'
                $entry['Message'] = "VHD type is $($vhdInfo.VhdType) — only Dynamic VHDs can be compacted"
                [void]$results.Add($entry)
                continue
            }

            Optimize-VHD -Path $vhd.FullName -Mode Full -ErrorAction Stop
            
            $newSize = (Get-Item $vhd.FullName).Length
            $savedBytes = $vhd.Length - $newSize
            $totalSaved += $savedBytes
            
            $entry['SizeAfterMB'] = [math]::Round($newSize / 1MB, 1)
            $entry['SavedMB'] = [math]::Round($savedBytes / 1MB, 1)
            $entry['Status'] = 'Compacted'
        } catch {
            $entry['Status'] = 'Failed'
            $entry['Error'] = $_.Exception.Message
        }
        
        [void]$results.Add($entry)
    }
}

$output = @{
    Timestamp     = [datetime]::UtcNow.ToString('o')
    ComputerName  = $env:COMPUTERNAME
    Summary       = @{
        Processed    = $results.Count
        Compacted    = ($results | Where-Object { $_.Status -eq 'Compacted' }).Count
        Skipped      = ($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        Failed       = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
        TotalSavedMB = [math]::Round($totalSaved / 1MB, 1)
    }
    Results       = $results
}

$output | ConvertTo-Json -Depth 3
