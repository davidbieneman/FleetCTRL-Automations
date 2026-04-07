# FSLogix: Profile Reset
# Backs up (renames) a user's profile container and deletes it so they get a fresh profile on next sign-in. Verifies user is not currently logged in. Returns backup path for potential restoration.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Profile Reset — backup and delete a user's profile container for fresh start.
.DESCRIPTION
    Renames (backs up) a user's VHD(X) container so they get a fresh profile
    on next sign-in. Verifies user is not currently logged in first.
.NOTES
    FleetCTRL Script Library | Category: Remediation & Repair
    Trigger: On-Demand | Admin Required: Yes | Destructive: Yes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetUsername
)

$ErrorActionPreference = 'SilentlyContinue'

# Check if user is currently logged in
$loggedInUsers = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty UserName
$qwinstaUsers = @()
try {
    # Use registry-based session detection (locale-safe)
    $sessions = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles\Sessions\*' -ErrorAction SilentlyContinue
    if ($sessions) {
        foreach ($s in $sessions) {
            if ($s.Username -and $s.Username -match $TargetUsername) {
                $qwinstaUsers += $s.Username
            }
        }
    }
} catch { }

$isLoggedIn = $false
if ($loggedInUsers -match $TargetUsername) { $isLoggedIn = $true }
if ($qwinstaUsers.Count -gt 0) { $isLoggedIn = $true }

if ($isLoggedIn) {
    @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        Status       = 'Blocked'
        Message      = "User '$TargetUsername' appears to be currently logged in — cannot reset while active"
    } | ConvertTo-Json -Depth 2
    return
}

# Find the user's profile container
$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$locations = @()
if ($profReg.VHDLocations) { $locations += @($profReg.VHDLocations) | ForEach-Object { $_.Trim() } }

$found = [System.Collections.ArrayList]::new()
$timestamp = [datetime]::UtcNow.ToString('yyyyMMdd_HHmmss')

foreach ($loc in $locations) {
    if (-not (Test-Path $loc)) { continue }
    
    $folders = Get-ChildItem -Path $loc -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $TargetUsername }
    
    foreach ($folder in $folders) {
        $vhdFiles = Get-ChildItem -Path $folder.FullName -Include '*.vhd','*.vhdx' -File -Recurse -ErrorAction SilentlyContinue
        
        foreach ($vhd in $vhdFiles) {
            # Check if attached
            $attached = $false
            try {
                if (Get-Module -ListAvailable -Name 'Hyper-V') {
                    $vhdInfo = Get-VHD -Path $vhd.FullName -ErrorAction Stop
                    $attached = $vhdInfo.Attached
                }
            } catch { }
            
            if ($attached) {
                [void]$found.Add(@{
                    File    = $vhd.FullName
                    SizeMB  = [math]::Round($vhd.Length / 1MB, 1)
                    Status  = 'Skipped'
                    Message = 'VHD is currently mounted — user may still be active'
                })
                continue
            }
            
            # Rename as backup
            $backupName = "$($vhd.BaseName)_BACKUP_$timestamp$($vhd.Extension)"
            $backupPath = Join-Path -Path $vhd.Directory.FullName -ChildPath $backupName
            
            try {
                Rename-Item -Path $vhd.FullName -NewName $backupName -ErrorAction Stop
                [void]$found.Add(@{
                    OriginalFile = $vhd.FullName
                    BackupFile   = $backupPath
                    SizeMB       = [math]::Round($vhd.Length / 1MB, 1)
                    Status       = 'Reset'
                    Message      = 'Container backed up — user will get a fresh profile on next login'
                })
            } catch {
                [void]$found.Add(@{
                    File    = $vhd.FullName
                    SizeMB  = [math]::Round($vhd.Length / 1MB, 1)
                    Status  = 'Failed'
                    Message = $_.Exception.Message
                })
            }
        }
    }
}

if ($found.Count -eq 0) {
    $output = @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        Status       = 'NotFound'
        Message      = "No profile containers found for user '$TargetUsername' in VHDLocations"
        SearchedPaths = $locations
    }
} else {
    $output = @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        TargetUser   = $TargetUsername
        Summary      = @{
            Reset   = ($found | Where-Object { $_.Status -eq 'Reset' }).Count
            Skipped = ($found | Where-Object { $_.Status -eq 'Skipped' }).Count
            Failed  = ($found | Where-Object { $_.Status -eq 'Failed' }).Count
        }
        Results      = $found
    }
}

$output | ConvertTo-Json -Depth 3
