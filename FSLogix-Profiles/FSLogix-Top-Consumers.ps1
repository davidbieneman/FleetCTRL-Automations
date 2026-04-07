# FSLogix: Top Consumers
# Reports the largest profile containers sorted by size with username, SID, identity type, last access date, and growth indicators.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Top Profile Consumers — largest containers sorted by size.
.NOTES
    FleetCTRL Script Library | Category: Profile Container
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param([int]$TopN = 25)

$ErrorActionPreference = 'SilentlyContinue'

$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$locations = @()
if ($profReg.VHDLocations) { $locations += @($profReg.VHDLocations) }
$locations = $locations | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() }

$consumers = [System.Collections.ArrayList]::new()

foreach ($loc in $locations) {
    if (-not (Test-Path $loc)) { continue }
    $vhdFiles = Get-ChildItem -Path $loc -Recurse -Include '*.vhd','*.vhdx' -File -ErrorAction SilentlyContinue
    foreach ($vhd in $vhdFiles) {
        $parentFolder = $vhd.Directory.Name
        $sid = if ($parentFolder -match '(S-1-\d+-\d+(?:-\d+)*)') { $Matches[1] } else { $null }
        $identityType = if ($sid -match '^S-1-5-21-') { 'AD_DS' } elseif ($sid -match '^S-1-12-1-') { 'Entra_ID' } elseif ($sid -match '^S-1-12-2-') { 'Entra_Guest' } else { 'Unknown' }
        $username = if ($sid) { $parentFolder -replace [regex]::Escape($sid), '' -replace '^_|_$', '' } else { $parentFolder }

        [void]$consumers.Add(@{
            Username     = $username
            SID          = $sid
            IdentityType = $identityType
            FileName     = $vhd.Name
            SizeMB       = [math]::Round($vhd.Length / 1MB, 1)
            SizeGB       = [math]::Round($vhd.Length / 1GB, 2)
            LastWriteUtc = $vhd.LastWriteTimeUtc.ToString('o')
            DaysSinceWrite = [math]::Round(([datetime]::UtcNow - $vhd.LastWriteTimeUtc).TotalDays, 0)
            Location     = $loc
        })
    }
}

$sorted = $consumers | Sort-Object -Property SizeMB -Descending | Select-Object -First $TopN
$totalGB = [math]::Round(($consumers | Measure-Object -Property SizeMB -Sum).Sum / 1024, 2)

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    TopN         = $TopN
    TotalContainers = $consumers.Count
    TotalSizeGB  = $totalGB
    TopConsumers = $sorted
}

$output | ConvertTo-Json -Depth 3
