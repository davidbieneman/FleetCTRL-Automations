# FSLogix: Config Audit
# Full dump of all FSLogix registry configuration including Profile Container, ODFC, Cloud Cache, logging, and GPO policy detection. Returns structured JSON with best-practice flags.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    FSLogix Configuration Audit — full registry dump with best-practice flags.
.DESCRIPTION
    Reads all FSLogix registry settings (Profile Container, ODFC, Cloud Cache, Logging)
    and returns structured JSON. Detects GPO vs local config, flags misconfigurations.
    Locale-safe: EN/DE/NL/JA/KO — pure registry reads, no text parsing.
.NOTES
    FleetCTRL Script Library | Category: Configuration & Discovery
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

function Read-RegistryValues {
    param([string]$Path)
    $result = @{}
    $key = Get-Item -Path $Path -ErrorAction SilentlyContinue
    if ($key) {
        foreach ($name in $key.GetValueNames()) {
            if ($name -ne '') {
                $result[$name] = $key.GetValue($name)
            }
        }
    }
    return $result
}

function Test-GpoSource {
    param([string]$SettingName, [string]$SubKey)
    $gpoPath = "HKLM:\SOFTWARE\Policies\FSLogix\$SubKey"
    $val = Get-ItemProperty -Path $gpoPath -Name $SettingName -ErrorAction SilentlyContinue
    return ($null -ne $val)
}

# --- Profile Container ---
$profilePath = 'HKLM:\SOFTWARE\FSLogix\Profiles'
$profileSettings = Read-RegistryValues -Path $profilePath

$profileConfig = @{
    Enabled                              = $profileSettings['Enabled']
    VHDLocations                         = $profileSettings['VHDLocations']
    CCDLocations                         = $profileSettings['CCDLocations']
    FlipFlopProfileDirectoryName         = $profileSettings['FlipFlopProfileDirectoryName']
    VolumeType                           = $profileSettings['VolumeType']
    SizeInMBs                            = $profileSettings['SizeInMBs']
    IsDynamic                            = $profileSettings['IsDynamic']
    ProfileType                          = $profileSettings['ProfileType']
    DeleteLocalProfileWhenVHDShouldApply = $profileSettings['DeleteLocalProfileWhenVHDShouldApply']
    VHDXSectorSize                       = $profileSettings['VHDXSectorSize']
    LockedRetryCount                     = $profileSettings['LockedRetryCount']
    LockedRetryInterval                  = $profileSettings['LockedRetryInterval']
    ReAttachIntervalSeconds              = $profileSettings['ReAttachIntervalSeconds']
    ReAttachRetryCount                   = $profileSettings['ReAttachRetryCount']
    CleanupInvalidSessions               = $profileSettings['CleanupInvalidSessions']
    AccessNetworkAsComputerObject        = $profileSettings['AccessNetworkAsComputerObject']
    PreventLoginWithFailure              = $profileSettings['PreventLoginWithFailure']
    PreventLoginWithTempProfile           = $profileSettings['PreventLoginWithTempProfile']
    ClearCacheOnLogoff                   = $profileSettings['ClearCacheOnLogoff']
    HealthyProvidersRequiredForRegister   = $profileSettings['HealthyProvidersRequiredForRegister']
    ConcurrentUserSessions               = $profileSettings['ConcurrentUserSessions']
    RoamRecycleBin                       = $profileSettings['RoamRecycleBin']
    VHDCompactDisk                       = $profileSettings['VHDCompactDisk']
    KeepLocalDir                         = $profileSettings['KeepLocalDir']
    SetTempToLocalPath                   = $profileSettings['SetTempToLocalPath']
    RedirXMLSourceFolder                 = $profileSettings['RedirXMLSourceFolder']
    SIDDirNamePattern                    = $profileSettings['SIDDirNamePattern']
    SIDDirNameMatch                      = $profileSettings['SIDDirNameMatch']
    RoamIdentity                         = $profileSettings['RoamIdentity']
    InstallAppxPackages                  = $profileSettings['InstallAppxPackages']
    AllRawValues                         = $profileSettings
}

# --- ODFC Container ---
$odfcPath = 'HKLM:\SOFTWARE\FSLogix\ODFC'
$odfcSettings = Read-RegistryValues -Path $odfcPath

$odfcConfig = @{
    Enabled                    = $odfcSettings['Enabled']
    VHDLocations               = $odfcSettings['VHDLocations']
    CCDLocations               = $odfcSettings['CCDLocations']
    IncludeOutlook             = $odfcSettings['IncludeOutlook']
    IncludeOneDrive            = $odfcSettings['IncludeOneDrive']
    IncludeTeams               = $odfcSettings['IncludeTeams']
    IncludeOneNote             = $odfcSettings['IncludeOneNote']
    IncludeOneNote_UWP         = $odfcSettings['IncludeOneNote_UWP']
    IncludeSharePoint          = $odfcSettings['IncludeSharePoint']
    IncludeOfficeActivation    = $odfcSettings['IncludeOfficeActivation']
    IncludeSkype               = $odfcSettings['IncludeSkype']
    IncludeOutlookPersonalization = $odfcSettings['IncludeOutlookPersonalization']
    MirrorLocalOSTToVHD        = $odfcSettings['MirrorLocalOSTToVHD']
    SizeInMBs                  = $odfcSettings['SizeInMBs']
    VolumeType                 = $odfcSettings['VolumeType']
    AllRawValues               = $odfcSettings
}

# --- Apps / Install Info ---
$appsPath = 'HKLM:\SOFTWARE\FSLogix\Apps'
$appsSettings = Read-RegistryValues -Path $appsPath
$installPath = $appsSettings['InstallPath']

$versionInfo = $null
if ($installPath) {
    $frxsvc = Join-Path -Path $installPath -ChildPath 'frxsvc.exe'
    if (Test-Path -Path $frxsvc) {
        $vi = (Get-Item -Path $frxsvc).VersionInfo
        $versionInfo = @{
            FileVersion    = $vi.FileVersion
            ProductVersion = $vi.ProductVersion
            ProductName    = $vi.ProductName
        }
    }
}

# --- Logging ---
$loggingPath = 'HKLM:\SOFTWARE\FSLogix\Logging'
$loggingSettings = Read-RegistryValues -Path $loggingPath

# --- GPO Detection ---
$gpoDetected = @{}
$gpoProfilePath = 'HKLM:\SOFTWARE\Policies\FSLogix\Profiles'
$gpoOdfcPath = 'HKLM:\SOFTWARE\Policies\FSLogix\ODFC'
if (Test-Path $gpoProfilePath) {
    $gpoDetected['ProfilesGPO'] = $true
    $gpoDetected['ProfilesGPOValues'] = Read-RegistryValues -Path $gpoProfilePath
} else {
    $gpoDetected['ProfilesGPO'] = $false
}
if (Test-Path $gpoOdfcPath) {
    $gpoDetected['ODFCGPO'] = $true
    $gpoDetected['ODFCGPOValues'] = Read-RegistryValues -Path $gpoOdfcPath
} else {
    $gpoDetected['ODFCGPO'] = $false
}

# --- Best Practice Flags ---
$flags = @()

if ($profileConfig.Enabled -ne 1) {
    $flags += @{ Level = 'Error'; Check = 'ProfileEnabled'; Message = 'FSLogix Profile Container is not enabled' }
}
if (-not $profileConfig.VHDLocations -and -not $profileConfig.CCDLocations) {
    $flags += @{ Level = 'Error'; Check = 'NoStorageConfigured'; Message = 'Neither VHDLocations nor CCDLocations is configured' }
}
if ($profileConfig.VHDLocations -and $profileConfig.CCDLocations) {
    $flags += @{ Level = 'Warning'; Check = 'DualStorageConflict'; Message = 'Both VHDLocations and CCDLocations are set — only one should be active' }
}
if ($profileConfig.VolumeType -eq 'VHD' -or $profileConfig.VolumeType -eq 0) {
    $flags += @{ Level = 'Warning'; Check = 'VHDFormat'; Message = 'Using VHD format instead of recommended VHDX' }
}
if ($profileConfig.IsDynamic -eq 0) {
    $flags += @{ Level = 'Warning'; Check = 'FixedDisk'; Message = 'Using fixed-size VHD instead of recommended dynamic' }
}
if ($profileConfig.FlipFlopProfileDirectoryName -ne 1) {
    $flags += @{ Level = 'Warning'; Check = 'FlipFlop'; Message = 'FlipFlopProfileDirectoryName not enabled — recommended for readability' }
}
if ($profileConfig.DeleteLocalProfileWhenVHDShouldApply -ne 1) {
    $flags += @{ Level = 'Warning'; Check = 'DeleteLocal'; Message = 'DeleteLocalProfileWhenVHDShouldApply not enabled — may cause local profile conflicts' }
}
if ($profileConfig.VHDXSectorSize -and $profileConfig.VHDXSectorSize -eq 512) {
    $flags += @{ Level = 'Warning'; Check = 'SectorSize'; Message = 'VHDXSectorSize is legacy 512 — 4096 recommended' }
}
if ($profileConfig.AccessNetworkAsComputerObject -eq 1) {
    $flags += @{ Level = 'Warning'; Check = 'NetworkAccess'; Message = 'AccessNetworkAsComputerObject=1 — should be 0 per 2026 best practice' }
}
if ($odfcConfig.IncludeSkype -eq 1) {
    $flags += @{ Level = 'Warning'; Check = 'SkypeDeprecated'; Message = 'IncludeSkype is enabled but Skype for Business reached EOL Oct 2025' }
}

# Config conflict detection
if ($profileConfig.SIDDirNamePattern -or $profileConfig.SIDDirNameMatch) {
    if ($profileConfig.FlipFlopProfileDirectoryName -eq 1) {
        $flags += @{ Level = 'Warning'; Check = 'NamingConflict'; Message = 'SIDDirNamePattern/Match set alongside FlipFlop — these may silently override each other' }
    }
}

# Container mode detection
$containerMode = 'Unknown'
if ($profileConfig.Enabled -eq 1 -and $odfcConfig.Enabled -eq 1) {
    $containerMode = 'Dual (Profile + ODFC)'
} elseif ($profileConfig.Enabled -eq 1) {
    $containerMode = 'Single (Profile Container includes O365)'
} elseif ($odfcConfig.Enabled -eq 1) {
    $containerMode = 'ODFC Only'
}

# --- Output ---
$output = @{
    Timestamp       = [datetime]::UtcNow.ToString('o')
    ComputerName    = $env:COMPUTERNAME
    ContainerMode   = $containerMode
    ProfileContainer = $profileConfig
    OfficeContainer  = $odfcConfig
    AppsInfo         = @{
        InstallPath = $installPath
        Version     = $versionInfo
    }
    Logging          = $loggingSettings
    GPODetection     = $gpoDetected
    BestPracticeFlags = $flags
}

$output | ConvertTo-Json -Depth 5
