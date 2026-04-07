# Install-FSLogix
# Downloads and installs the latest FSLogix Apps with best-practice registry configuration, Defender exclusions, and version detection. Supports fresh install and upgrade.
#Category: Maintenance
#Run On: on_demand
#Timeout: 600
#Execution Mode: serial

#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install or upgrade FSLogix Apps with best-practice configuration.
.DESCRIPTION
    Downloads the latest FSLogix Apps from Microsoft, installs silently,
    and configures recommended registry settings for Azure Virtual Desktop.
    Detects existing installations and upgrades if a newer version is available.
    All operations are locale-safe (registry paths, numeric exit codes only).
.NOTES
    FleetCTRL Automation Library | Category: Maintenance
    Trigger: On-Demand / Provisioning | Admin Required: Yes | Destructive: No
#>
[CmdletBinding()]
param(
    [string]$VHDLocations = '',
    [string]$CCDLocations = '',
    [int]$SizeInMBs = 30000,
    [switch]$SkipConfig,
    [switch]$ForceReinstall
)

$ErrorActionPreference = 'Stop'
$logDir = 'C:\ProgramData\Liquidware\FleetCTRL\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "Install-FSLogix_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function Log { param([string]$msg) Add-Content -Path $logFile -Value "$(Get-Date -Format 'HH:mm:ss') $msg" }

$result = @{
    Timestamp     = [datetime]::UtcNow.ToString('o')
    ComputerName  = $env:COMPUTERNAME
    Action        = 'install'
    PreviousVersion = $null
    InstalledVersion = $null
    ConfigApplied = $false
    RebootRequired = $false
    Steps         = [System.Collections.ArrayList]::new()
}

function Add-Step {
    param([string]$Name, [string]$Status, [string]$Detail)
    [void]$result.Steps.Add(@{ Name = $Name; Status = $Status; Detail = $Detail })
    Log "$Name : $Status - $Detail"
}

# ===== DETECT EXISTING INSTALLATION =====
$existingVersion = $null
$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
$existingVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallVersion' -ErrorAction SilentlyContinue).InstallVersion

if ($existingVersion) {
    $result.PreviousVersion = $existingVersion
    Add-Step 'Detect Existing' 'Info' "FSLogix $existingVersion found at $installPath"
    if (-not $ForceReinstall) {
        $result.Action = 'upgrade_check'
    }
} else {
    Add-Step 'Detect Existing' 'Info' 'FSLogix not installed'
}

# ===== CHECK PENDING REBOOT =====
$pendingReboot = $false
$rbCheck = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' -ErrorAction SilentlyContinue
if ($rbCheck) { $pendingReboot = $true }
$rbCheck2 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' -ErrorAction SilentlyContinue
if ($rbCheck2) { $pendingReboot = $true }

if ($pendingReboot) {
    Add-Step 'Pending Reboot Check' 'Warning' 'System has a pending reboot — install may not complete correctly'
} else {
    Add-Step 'Pending Reboot Check' 'Pass' 'No pending reboot'
}

# ===== DOWNLOAD =====
$downloadUrl = 'https://aka.ms/fslogix_download'
$zipPath = Join-Path $env:TEMP 'FSLogix.zip'
$extractPath = Join-Path $env:TEMP 'FSLogix'

try {
    Add-Step 'Download' 'Running' "Downloading from $downloadUrl"
    # Clean up previous downloads
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
    Add-Step 'Download' 'Pass' "Downloaded $(([math]::Round((Get-Item $zipPath).Length / 1MB, 1))) MB"
} catch {
    Add-Step 'Download' 'Fail' $_.Exception.Message
    $result | ConvertTo-Json -Depth 3
    exit 1
}

# ===== EXTRACT =====
try {
    Add-Step 'Extract' 'Running' 'Extracting ZIP archive'
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    $installer = Get-ChildItem -Path $extractPath -Filter 'FSLogixAppsSetup.exe' -Recurse |
        Where-Object { $_.DirectoryName -match 'x64' } | Select-Object -First 1
    if (-not $installer) {
        # Fallback: any FSLogixAppsSetup.exe
        $installer = Get-ChildItem -Path $extractPath -Filter 'FSLogixAppsSetup.exe' -Recurse | Select-Object -First 1
    }
    if (-not $installer) {
        Add-Step 'Extract' 'Fail' 'FSLogixAppsSetup.exe not found in archive'
        $result | ConvertTo-Json -Depth 3
        exit 1
    }
    Add-Step 'Extract' 'Pass' "Found $($installer.FullName)"
} catch {
    Add-Step 'Extract' 'Fail' $_.Exception.Message
    $result | ConvertTo-Json -Depth 3
    exit 1
}

# ===== VERSION CHECK (skip if already up-to-date) =====
if ($existingVersion -and -not $ForceReinstall) {
    # Get downloaded version from the EXE file info
    $downloadedVersion = (Get-Item $installer.FullName).VersionInfo.FileVersion
    if ($downloadedVersion -and $existingVersion) {
        try {
            $existing = [System.Version]($existingVersion -replace '[^0-9.]', '')
            $downloaded = [System.Version]($downloadedVersion -replace '[^0-9.]', '')
            if ($existing -ge $downloaded) {
                Add-Step 'Version Check' 'Pass' "Already up to date ($existingVersion >= $downloadedVersion)"
                $result.Action = 'already_current'
                $result.InstalledVersion = $existingVersion
                # Still apply config if requested
                if (-not $SkipConfig) {
                    # Jump to config section
                } else {
                    $result | ConvertTo-Json -Depth 3
                    exit 0
                }
            } else {
                Add-Step 'Version Check' 'Info' "Upgrade available: $existingVersion -> $downloadedVersion"
                $result.Action = 'upgrade'
            }
        } catch {
            Add-Step 'Version Check' 'Warning' "Could not compare versions: $($_.Exception.Message)"
        }
    }
}

# ===== INSTALL =====
if ($result.Action -ne 'already_current') {
    try {
        # Stop services before upgrade
        if ($existingVersion) {
            Stop-Service -Name 'frxccds' -Force -ErrorAction SilentlyContinue
            Stop-Service -Name 'frxsvc' -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        $installLog = Join-Path $logDir "FSLogixAppsSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Add-Step 'Install' 'Running' "Installing with /install /quiet /norestart"

        $proc = Start-Process -FilePath $installer.FullName -ArgumentList "/install /quiet /norestart /log `"$installLog`"" -Wait -PassThru -NoNewWindow
        $exitCode = $proc.ExitCode

        switch ($exitCode) {
            0       { Add-Step 'Install' 'Pass' 'Installed successfully (no reboot needed)' }
            3010    { Add-Step 'Install' 'Pass' 'Installed successfully (reboot required)'; $result.RebootRequired = $true }
            1641    { Add-Step 'Install' 'Pass' 'Installed successfully (auto-reboot scheduled)'; $result.RebootRequired = $true }
            default { Add-Step 'Install' 'Fail' "Installer exited with code $exitCode — check $installLog"; $result | ConvertTo-Json -Depth 3; exit 1 }
        }

        # Read installed version
        Start-Sleep -Seconds 2
        $result.InstalledVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallVersion' -ErrorAction SilentlyContinue).InstallVersion
        if ($result.InstalledVersion) {
            Add-Step 'Version' 'Pass' "Installed version: $($result.InstalledVersion)"
        }
    } catch {
        Add-Step 'Install' 'Fail' $_.Exception.Message
        $result | ConvertTo-Json -Depth 3
        exit 1
    }
}

# ===== CONFIGURE REGISTRY =====
if (-not $SkipConfig) {
    try {
        $regPath = 'HKLM:\SOFTWARE\FSLogix\Profiles'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        # Enable profile container
        Set-ItemProperty -Path $regPath -Name 'Enabled' -Value 1 -Type DWord
        Add-Step 'Config: Enabled' 'Pass' 'Profile Container enabled'

        # Storage location
        if ($VHDLocations) {
            Set-ItemProperty -Path $regPath -Name 'VHDLocations' -Value $VHDLocations -Type String
            Add-Step 'Config: VHDLocations' 'Pass' "Set to $VHDLocations"
        } elseif ($CCDLocations) {
            Set-ItemProperty -Path $regPath -Name 'CCDLocations' -Value $CCDLocations -Type String
            Add-Step 'Config: CCDLocations' 'Pass' "Set to $CCDLocations"
        } else {
            $existingVHD = (Get-ItemProperty -Path $regPath -Name 'VHDLocations' -ErrorAction SilentlyContinue).VHDLocations
            $existingCCD = (Get-ItemProperty -Path $regPath -Name 'CCDLocations' -ErrorAction SilentlyContinue).CCDLocations
            if (-not $existingVHD -and -not $existingCCD) {
                Add-Step 'Config: Storage' 'Warning' 'No VHDLocations or CCDLocations provided — profile containers will not work until storage is configured'
            } else {
                Add-Step 'Config: Storage' 'Info' 'Using existing storage configuration'
            }
        }

        # Best practice settings
        Set-ItemProperty -Path $regPath -Name 'VolumeType' -Value 'VHDX' -Type String
        Set-ItemProperty -Path $regPath -Name 'FlipFlopProfileDirectoryName' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'DeleteLocalProfileWhenVHDShouldApply' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'IsDynamic' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'SizeInMBs' -Value $SizeInMBs -Type DWord
        Set-ItemProperty -Path $regPath -Name 'LockedRetryCount' -Value 3 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'LockedRetryInterval' -Value 15 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'ReAttachRetryCount' -Value 3 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'ReAttachIntervalSeconds' -Value 15 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'PreventLoginWithFailure' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'PreventLoginWithTempProfile' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'VHDCompactDisk' -Value 1 -Type DWord

        Add-Step 'Config: Best Practices' 'Pass' 'Applied: VHDX, FlipFlop, DeleteLocal, Dynamic, PreventLoginWithFailure, PreventLoginWithTempProfile, VHDCompact'
        $result.ConfigApplied = $true
    } catch {
        Add-Step 'Config' 'Fail' $_.Exception.Message
    }
}

# ===== DEFENDER EXCLUSIONS =====
try {
    $exclusionsAdded = @()
    $extExclusions = @('.vhd', '.vhdx', '.cim')
    foreach ($ext in $extExclusions) {
        $existing = (Get-MpPreference -ErrorAction Stop).ExclusionExtension
        if ($existing -notcontains $ext) {
            Add-MpPreference -ExclusionExtension $ext -ErrorAction Stop
            $exclusionsAdded += "ext:$ext"
        }
    }

    $procExclusions = @(
        'C:\Program Files\FSLogix\Apps\frxsvc.exe',
        'C:\Program Files\FSLogix\Apps\frxccds.exe',
        'C:\Program Files\FSLogix\Apps\frx.exe'
    )
    foreach ($proc in $procExclusions) {
        $existing = (Get-MpPreference -ErrorAction Stop).ExclusionProcess
        if (-not ($existing | Where-Object { $_ -like "*$([System.IO.Path]::GetFileName($proc))" })) {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction Stop
            $exclusionsAdded += "proc:$([System.IO.Path]::GetFileName($proc))"
        }
    }

    Add-MpPreference -ExclusionPath 'C:\Program Files\FSLogix\Apps\' -ErrorAction SilentlyContinue

    if ($exclusionsAdded.Count -gt 0) {
        Add-Step 'Defender Exclusions' 'Pass' "Added: $($exclusionsAdded -join ', ')"
    } else {
        Add-Step 'Defender Exclusions' 'Pass' 'All exclusions already configured'
    }
} catch {
    Add-Step 'Defender Exclusions' 'Warning' "Could not configure: $($_.Exception.Message)"
}

# ===== CLEANUP =====
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue

if ($result.RebootRequired) {
    Add-Step 'Summary' 'Warning' 'Installation complete — REBOOT REQUIRED for FSLogix services and drivers to start'
} else {
    Add-Step 'Summary' 'Pass' 'Installation and configuration complete'
}

$result | ConvertTo-Json -Depth 3
