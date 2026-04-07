# FSLogix: OST/PST Inventory
# Finds Outlook OST/PST data files across user profiles and containers. Reports sizes, locations, and flags oversized files. Identifies whether data is inside ODFC vs profile container vs local disk.
#Category: FSLogix: Office 365
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    OST/PST File Inventory — find Outlook data files across profiles.
.NOTES
    FleetCTRL Script Library | Category: Office 365 Container
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param([int]$OversizeThresholdMB = 5120)

$ErrorActionPreference = 'SilentlyContinue'

$usersRoot = Join-Path -Path $env:SystemDrive -ChildPath 'Users'
$userDirs = Get-ChildItem -Path $usersRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('Public', 'Default', 'Default User', 'All Users') }

$files = [System.Collections.ArrayList]::new()
$totalSizeBytes = 0

foreach ($userDir in $userDirs) {
    $outlookFiles = Get-ChildItem -Path $userDir.FullName -Recurse -Include '*.ost','*.pst' -File -ErrorAction SilentlyContinue
    foreach ($f in $outlookFiles) {
        $sizeMB = [math]::Round($f.Length / 1MB, 1)
        $totalSizeBytes += $f.Length
        $location = if ($f.FullName -match 'ODFC') { 'ODFC_Container' }
            elseif ($f.FullName -match 'Profile_') { 'Profile_Container' }
            else { 'Local_Disk' }

        [void]$files.Add(@{
            User         = $userDir.Name
            FileName     = $f.Name
            Extension    = $f.Extension.ToUpper()
            SizeMB       = $sizeMB
            IsOversized  = ($sizeMB -gt $OversizeThresholdMB)
            Location     = $location
            FullPath     = $f.FullName
            LastWriteUtc = $f.LastWriteTimeUtc.ToString('o')
        })
    }
}

$output = @{
    Timestamp      = [datetime]::UtcNow.ToString('o')
    ComputerName   = $env:COMPUTERNAME
    OversizeThresholdMB = $OversizeThresholdMB
    Summary        = @{
        TotalFiles     = $files.Count
        TotalSizeGB    = [math]::Round($totalSizeBytes / 1GB, 2)
        OstFiles       = ($files | Where-Object { $_.Extension -eq '.OST' }).Count
        PstFiles       = ($files | Where-Object { $_.Extension -eq '.PST' }).Count
        OversizedFiles = ($files | Where-Object { $_.IsOversized }).Count
    }
    Files          = $files | Sort-Object -Property SizeMB -Descending
}

$output | ConvertTo-Json -Depth 3
