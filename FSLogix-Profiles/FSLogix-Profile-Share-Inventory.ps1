# FSLogix: Profile Share Inventory
# Enumerates ALL profile containers on VHDLocations shares — not just active sessions. Detects identity type (AD DS, Entra ID, Entra Guest), container type, ODFC presence, and stale profiles.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 180
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Profile Share Inventory — enumerate ALL containers on VHDLocations.
.DESCRIPTION
    Scans VHDLocations shares for all profile containers, not just active sessions.
    Detects identity type (AD DS, Entra ID, Entra Guest), container type, ODFC, stale profiles.
.NOTES
    FleetCTRL Script Library | Category: Profile Container
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param(
    [int]$StaleDaysThreshold = 90,
    [int]$MaxProfiles = 500
)

$ErrorActionPreference = 'SilentlyContinue'

function Get-IdentityType {
    param([string]$SID)
    if ($SID -match '^S-1-5-21-') { return 'AD_DS' }
    if ($SID -match '^S-1-12-1-') { return 'Entra_ID' }
    if ($SID -match '^S-1-12-2-') { return 'Entra_Guest' }
    return 'Unknown'
}

function Extract-SidFromFolder {
    param([string]$FolderName)
    # Supports both SID_username and username_SID (FlipFlop) patterns
    if ($FolderName -match '(S-1-\d+-\d+(?:-\d+)*)') {
        return $Matches[1]
    }
    return $null
}

function Extract-UsernameFromFolder {
    param([string]$FolderName, [string]$SID)
    if (-not $SID) { return $FolderName }
    $name = $FolderName -replace [regex]::Escape($SID), '' -replace '^_|_$', ''
    if ($name) { return $name }
    return $FolderName
}

$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$odfcReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\ODFC' -ErrorAction SilentlyContinue

$locations = @()
if ($profReg.VHDLocations) { $locations += @($profReg.VHDLocations) }
$locations = $locations | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() } | Select-Object -Unique

$odfcLocations = @()
if ($odfcReg.VHDLocations) { $odfcLocations += @($odfcReg.VHDLocations) }

$profiles = [System.Collections.ArrayList]::new()
$staleCutoff = [datetime]::UtcNow.AddDays(-$StaleDaysThreshold)
$totalSizeBytes = 0
$staleCount = 0

foreach ($loc in $locations) {
    if (-not (Test-Path -Path $loc)) { continue }
    
    $folders = Get-ChildItem -Path $loc -Directory -ErrorAction SilentlyContinue |
        Select-Object -First $MaxProfiles
    
    foreach ($folder in $folders) {
        $sid = Extract-SidFromFolder -FolderName $folder.Name
        if (-not $sid) { continue }
        
        $username = Extract-UsernameFromFolder -FolderName $folder.Name -SID $sid
        $identityType = Get-IdentityType -SID $sid
        
        # Find VHD/VHDX files
        $vhdFiles = Get-ChildItem -Path $folder.FullName -Include '*.vhd','*.vhdx' -Recurse -File -ErrorAction SilentlyContinue
        $profileVhd = $vhdFiles | Where-Object { $_.Name -match '^Profile_' } | Select-Object -First 1
        $odfcVhd = $vhdFiles | Where-Object { $_.Name -match '^ODFC_' } | Select-Object -First 1
        
        # Also check for ODFC sibling folder
        if (-not $odfcVhd) {
            $odfcSibling = Join-Path -Path $loc -ChildPath "ODFC_$($folder.Name)"
            if (Test-Path $odfcSibling) {
                $odfcVhd = Get-ChildItem -Path $odfcSibling -Include '*.vhd','*.vhdx' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            }
        }
        
        $profileSizeBytes = if ($profileVhd) { $profileVhd.Length } else { 0 }
        $odfcSizeBytes = if ($odfcVhd) { $odfcVhd.Length } else { 0 }
        $lastWriteUtc = if ($profileVhd) { $profileVhd.LastWriteTimeUtc } else { $folder.LastWriteTimeUtc }
        $isStale = $lastWriteUtc -lt $staleCutoff
        
        $totalSizeBytes += $profileSizeBytes + $odfcSizeBytes
        if ($isStale) { $staleCount++ }
        
        [void]$profiles.Add(@{
            Username       = $username
            SID            = $sid
            IdentityType   = $identityType
            FolderName     = $folder.Name
            FolderPath     = $folder.FullName
            ProfileVHD     = if ($profileVhd) { $profileVhd.Name } else { $null }
            ProfileSizeMB  = [math]::Round($profileSizeBytes / 1MB, 1)
            HasODFC        = [bool]$odfcVhd
            OdfcSizeMB     = [math]::Round($odfcSizeBytes / 1MB, 1)
            LastWriteUtc   = $lastWriteUtc.ToString('o')
            IsStale        = $isStale
            DaysSinceAccess = [math]::Round(([datetime]::UtcNow - $lastWriteUtc).TotalDays, 0)
        })
    }
}

# Identity type summary
$identitySummary = $profiles | Group-Object -Property IdentityType |
    ForEach-Object { @{ Type = $_.Name; Count = $_.Count } }

$output = @{
    Timestamp       = [datetime]::UtcNow.ToString('o')
    ComputerName    = $env:COMPUTERNAME
    VHDLocations    = $locations
    Summary         = @{
        TotalProfiles      = $profiles.Count
        TotalSizeGB        = [math]::Round($totalSizeBytes / 1GB, 2)
        StaleProfiles      = $staleCount
        StaleDaysThreshold = $StaleDaysThreshold
        IdentityTypes      = $identitySummary
    }
    Profiles        = $profiles | Sort-Object -Property ProfileSizeMB -Descending
}

$output | ConvertTo-Json -Depth 4
