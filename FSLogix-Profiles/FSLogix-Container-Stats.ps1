# FSLogix: Container Stats
# Detailed VHD/VHDX statistics including file size, virtual size, white space reclaimable, format, dynamic/fixed, owner, and attachment status. Requires Hyper-V module.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 180
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Profile Container Stats — detailed VHD/VHDX statistics.
.DESCRIPTION
    Reports file size, virtual size, white space, format, dynamic/fixed,
    owner, and attachment status for profile containers. Requires Hyper-V module.
.NOTES
    FleetCTRL Script Library | Category: Profile Container
    Trigger: On-Demand | Admin Required: Yes | Destructive: No
#>
[CmdletBinding()]
param(
    [int]$MaxContainers = 100
)

$ErrorActionPreference = 'SilentlyContinue'

$hasHyperV = [bool](Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue)
$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$locations = @()
if ($profReg.VHDLocations) { $locations += @($profReg.VHDLocations) }
$locations = $locations | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }

$containers = [System.Collections.ArrayList]::new()
$totalFileSizeBytes = 0
$totalVirtualSizeBytes = 0

foreach ($loc in $locations) {
    if (-not (Test-Path $loc)) { continue }
    
    $vhdFiles = Get-ChildItem -Path $loc -Recurse -Include '*.vhd','*.vhdx' -File -ErrorAction SilentlyContinue |
        Select-Object -First $MaxContainers
    
    foreach ($vhd in $vhdFiles) {
        $entry = @{
            FileName       = $vhd.Name
            FullPath       = $vhd.FullName
            FileSizeMB     = [math]::Round($vhd.Length / 1MB, 1)
            LastWriteUtc   = $vhd.LastWriteTimeUtc.ToString('o')
            Extension      = $vhd.Extension.ToUpper()
        }
        
        $totalFileSizeBytes += $vhd.Length
        
        # Get VHD details if Hyper-V module available
        if ($hasHyperV) {
            try {
                $vhdInfo = Get-VHD -Path $vhd.FullName -ErrorAction Stop
                $entry['VirtualSizeMB'] = [math]::Round($vhdInfo.Size / 1MB, 1)
                $entry['WhiteSpaceMB'] = [math]::Round(($vhdInfo.Size - $vhd.Length) / 1MB, 1)
                $entry['WhiteSpacePercent'] = if ($vhdInfo.Size -gt 0) { [math]::Round((($vhdInfo.Size - $vhd.Length) / $vhdInfo.Size) * 100, 1) } else { 0 }
                $entry['VhdType'] = $vhdInfo.VhdType.ToString()
                $entry['Attached'] = $vhdInfo.Attached
                $entry['BlockSize'] = $vhdInfo.BlockSize
                $totalVirtualSizeBytes += $vhdInfo.Size
            } catch {
                $entry['VhdInfoError'] = $_.Exception.Message
            }
        }
        
        # Get ACL owner
        try {
            $acl = Get-Acl -Path $vhd.FullName -ErrorAction Stop
            $entry['Owner'] = $acl.Owner
        } catch { }
        
        [void]$containers.Add($entry)
    }
}

$output = @{
    Timestamp      = [datetime]::UtcNow.ToString('o')
    ComputerName   = $env:COMPUTERNAME
    HyperVAvailable = $hasHyperV
    Summary        = @{
        TotalContainers     = $containers.Count
        TotalFileSizeGB     = [math]::Round($totalFileSizeBytes / 1GB, 2)
        TotalVirtualSizeGB  = if ($hasHyperV) { [math]::Round($totalVirtualSizeBytes / 1GB, 2) } else { $null }
        TotalWhiteSpaceGB   = if ($hasHyperV) { [math]::Round(($totalVirtualSizeBytes - $totalFileSizeBytes) / 1GB, 2) } else { $null }
    }
    Containers     = $containers | Sort-Object -Property FileSizeMB -Descending
}

$output | ConvertTo-Json -Depth 3
