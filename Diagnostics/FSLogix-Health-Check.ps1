# FSLogix: Health Check
# 30+ automated checks across services, configuration, Defender exclusions, storage, Cloud Cache, and version awareness. Returns pass/warn/fail per check with remediation guidance.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    FSLogix Comprehensive Health Check — 30+ automated checks.
.DESCRIPTION
    Validates services, configuration best practices, Defender exclusions,
    storage accessibility, Cloud Cache, and version-specific issues.
    Returns pass/warn/fail per check with remediation guidance.
    Locale-safe: CIM-based, service names not display names.
.NOTES
    FleetCTRL Script Library | Category: Health & Diagnostics
    Trigger: On-Demand / Boot | Admin Required: No (Defender checks need admin) | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$checks = [System.Collections.ArrayList]::new()

function Add-Check {
    param([string]$Category, [string]$Name, [string]$Status, [string]$Message, [string]$Remediation)
    [void]$checks.Add(@{
        Category    = $Category
        Name        = $Name
        Status      = $Status   # Pass, Warning, Fail, Info
        Message     = $Message
        Remediation = $Remediation
    })
}

# ===== SERVICES =====
$frxsvc = Get-Service -Name 'frxsvc' -ErrorAction SilentlyContinue
if ($frxsvc) {
    if ($frxsvc.Status -eq 'Running') {
        Add-Check 'Services' 'FSLogix Service' 'Pass' 'frxsvc is running' $null
    } else {
        Add-Check 'Services' 'FSLogix Service' 'Fail' "frxsvc status: $($frxsvc.Status)" 'Start the FSLogix Apps Services service'
    }
    $startType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='frxsvc'" -ErrorAction SilentlyContinue).StartMode
    if ($startType -ne 'Auto') {
        Add-Check 'Services' 'FSLogix Startup Type' 'Warning' "frxsvc startup: $startType" 'Set frxsvc to Automatic startup'
    } else {
        Add-Check 'Services' 'FSLogix Startup Type' 'Pass' 'frxsvc startup is Automatic' $null
    }
} else {
    Add-Check 'Services' 'FSLogix Service' 'Fail' 'frxsvc service not found — FSLogix may not be installed' 'Install FSLogix Apps'
}

# Cloud Cache service
$ccdLocations = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'CCDLocations' -ErrorAction SilentlyContinue).CCDLocations
if ($ccdLocations) {
    $frxccds = Get-Service -Name 'frxccds' -ErrorAction SilentlyContinue
    if ($frxccds -and $frxccds.Status -eq 'Running') {
        Add-Check 'Services' 'Cloud Cache Service' 'Pass' 'frxccds is running' $null
    } elseif ($frxccds) {
        Add-Check 'Services' 'Cloud Cache Service' 'Fail' "frxccds status: $($frxccds.Status)" 'Start the FSLogix Cloud Cache service'
    } else {
        Add-Check 'Services' 'Cloud Cache Service' 'Fail' 'frxccds not found but CCDLocations is configured' 'Reinstall FSLogix or verify Cloud Cache component'
    }
}

# Microsoft.FSLogix PowerShell Module
$fsModule = Get-Module -ListAvailable -Name 'Microsoft.FSLogix' -ErrorAction SilentlyContinue
if ($fsModule) {
    Add-Check 'Services' 'FSLogix PowerShell Module' 'Pass' "Microsoft.FSLogix module available (v$($fsModule.Version))" $null
} else {
    Add-Check 'Services' 'FSLogix PowerShell Module' 'Info' 'Microsoft.FSLogix module not found — Cloud Cache troubleshooting limited' 'Module ships with FSLogix 2026+'
}

# ===== CONFIGURATION =====
$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue

if ($profReg) {
    # Enabled
    if ($profReg.Enabled -eq 1) {
        Add-Check 'Configuration' 'Profile Enabled' 'Pass' 'Profile Container is enabled' $null
    } else {
        Add-Check 'Configuration' 'Profile Enabled' 'Fail' 'Profile Container is not enabled' 'Set HKLM:\SOFTWARE\FSLogix\Profiles\Enabled = 1'
    }

    # Storage configured
    $vhdLoc = $profReg.VHDLocations
    $ccdLoc = $profReg.CCDLocations
    if ($vhdLoc -or $ccdLoc) {
        Add-Check 'Configuration' 'Storage Configured' 'Pass' "VHDLocations=$(if($vhdLoc){'Set'}else{'NotSet'}), CCDLocations=$(if($ccdLoc){'Set'}else{'NotSet'})" $null
    } else {
        Add-Check 'Configuration' 'Storage Configured' 'Fail' 'No VHDLocations or CCDLocations configured' 'Configure a storage path for profile containers'
    }

    # Dual storage conflict
    if ($vhdLoc -and $ccdLoc) {
        Add-Check 'Configuration' 'Storage Conflict' 'Warning' 'Both VHDLocations and CCDLocations are set' 'Use only VHDLocations OR CCDLocations, not both'
    }

    # Volume Type
    if ($profReg.VolumeType -eq 'VHDX' -or $profReg.VolumeType -eq 1) {
        Add-Check 'Configuration' 'Volume Type' 'Pass' 'Using VHDX format' $null
    } else {
        Add-Check 'Configuration' 'Volume Type' 'Warning' 'Not using VHDX format' 'Set VolumeType to VHDX for better performance and resilience'
    }

    # Dynamic Disk
    if ($profReg.IsDynamic -eq 1 -or $null -eq $profReg.IsDynamic) {
        Add-Check 'Configuration' 'Dynamic Disk' 'Pass' 'Using dynamic VHD (or default)' $null
    } else {
        Add-Check 'Configuration' 'Dynamic Disk' 'Warning' 'Using fixed-size VHD' 'Set IsDynamic=1 for space efficiency'
    }

    # Size configured
    if ($profReg.SizeInMBs -and $profReg.SizeInMBs -gt 0) {
        Add-Check 'Configuration' 'Size Limit' 'Pass' "Max container size: $($profReg.SizeInMBs) MB" $null
    } else {
        Add-Check 'Configuration' 'Size Limit' 'Warning' 'No SizeInMBs configured — containers can grow unbounded' 'Set SizeInMBs (recommended: 30000 = 30GB)'
    }

    # FlipFlop
    if ($profReg.FlipFlopProfileDirectoryName -eq 1) {
        Add-Check 'Configuration' 'FlipFlop Naming' 'Pass' 'FlipFlopProfileDirectoryName enabled' $null
    } else {
        Add-Check 'Configuration' 'FlipFlop Naming' 'Warning' 'FlipFlopProfileDirectoryName not enabled' 'Enable for username_SID naming (easier browsing)'
    }

    # DeleteLocalProfile
    if ($profReg.DeleteLocalProfileWhenVHDShouldApply -eq 1) {
        Add-Check 'Configuration' 'Delete Local Profile' 'Pass' 'DeleteLocalProfileWhenVHDShouldApply enabled' $null
    } else {
        Add-Check 'Configuration' 'Delete Local Profile' 'Warning' 'DeleteLocalProfileWhenVHDShouldApply not enabled' 'Enable to prevent local profile conflicts'
    }

    # Sector Size
    if ($profReg.VHDXSectorSize -eq 512) {
        Add-Check 'Configuration' 'VHDX Sector Size' 'Warning' 'VHDXSectorSize is legacy 512' 'Set to 4096 for modern performance'
    } elseif ($profReg.VHDXSectorSize -eq 4096 -or $null -eq $profReg.VHDXSectorSize) {
        Add-Check 'Configuration' 'VHDX Sector Size' 'Pass' 'VHDXSectorSize is 4096 (or default)' $null
    }

    # AccessNetworkAsComputerObject
    if ($profReg.AccessNetworkAsComputerObject -eq 1) {
        Add-Check 'Configuration' 'Network Access Mode' 'Warning' 'AccessNetworkAsComputerObject=1' 'Set to 0 per FSLogix 2026 best practice'
    } else {
        Add-Check 'Configuration' 'Network Access Mode' 'Pass' 'AccessNetworkAsComputerObject is 0/default' $null
    }

    # Config conflict detection
    if (($profReg.SIDDirNamePattern -or $profReg.SIDDirNameMatch) -and $profReg.FlipFlopProfileDirectoryName -eq 1) {
        Add-Check 'Configuration' 'Naming Conflict' 'Warning' 'SIDDirNamePattern/Match set alongside FlipFlop' 'These settings can silently override each other'
    }

    # ConcurrentUserSessions
    if ($profReg.ConcurrentUserSessions -and $profReg.ConcurrentUserSessions -gt 0) {
        Add-Check 'Configuration' 'Concurrent Sessions' 'Info' "ConcurrentUserSessions: $($profReg.ConcurrentUserSessions)" $null
    }
} else {
    Add-Check 'Configuration' 'Registry Present' 'Fail' 'FSLogix Profiles registry key not found' 'Install and configure FSLogix'
}

# ===== VERSION AWARENESS (CU1 detection) =====
$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
if ($installPath) {
    $frxExe = Join-Path -Path $installPath -ChildPath 'frxsvc.exe'
    if (Test-Path $frxExe) {
        $ver = (Get-Item $frxExe).VersionInfo.FileVersion
        
        # Check for 26.01 RTM vs CU1
        $odfcReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\ODFC' -ErrorAction SilentlyContinue
        $odfcEnabled = $odfcReg -and $odfcReg.Enabled -eq 1
        $cleanupEnabled = $profReg -and $profReg.CleanupInvalidSessions -eq 1
        
        if ($ver -match '^2\.9\.89') {
            # Likely 26.01 RTM
            if ($cleanupEnabled -and $odfcEnabled) {
                Add-Check 'Version' 'CU1 ODFC Bug' 'Fail' 'FSLogix 26.01 RTM with CleanupInvalidSessions=1 and ODFC enabled — known ODFC container creation bug' 'Upgrade to CU1 or disable CleanupInvalidSessions immediately'
            } elseif ($odfcEnabled) {
                Add-Check 'Version' 'CU1 ODFC Warning' 'Warning' 'FSLogix 26.01 RTM with ODFC configured — do NOT enable CleanupInvalidSessions' 'Upgrade to CU1 to safely use CleanupInvalidSessions'
            }
            Add-Check 'Version' 'CU1 Upgrade' 'Warning' "FSLogix version $ver appears to be 26.01 RTM" 'Upgrade to CU1 for bug fixes and stability improvements'
        }

        # IncludeSkype deprecation
        if ($odfcReg -and $odfcReg.IncludeSkype -eq 1) {
            Add-Check 'Version' 'Skype Deprecation' 'Warning' 'IncludeSkype is enabled — Skype for Business EOL Oct 2025' 'Disable IncludeSkype to reduce container bloat'
        }

        # Feature retirements (25.02+)
        $frxTray = Join-Path -Path $installPath -ChildPath 'frxtray.exe'
        if (-not (Test-Path $frxTray)) {
            Add-Check 'Version' 'FRXTray Retired' 'Info' 'frxtray.exe not present — retired in FSLogix 25.02+' 'Use FSLogix-Status script or Profile Toolkit for status monitoring'
        }
    }
}

# ===== DEFENDER EXCLUSIONS =====
try {
    $prefs = Get-MpPreference -ErrorAction Stop
    
    $extExclusions = @('.vhd', '.vhdx', '.cim')
    foreach ($ext in $extExclusions) {
        if ($prefs.ExclusionExtension -contains $ext) {
            Add-Check 'Defender' "Extension $ext" 'Pass' "$ext extension is excluded" $null
        } else {
            Add-Check 'Defender' "Extension $ext" 'Warning' "$ext extension is NOT excluded from Defender" "Run: Add-MpPreference -ExclusionExtension '$ext'"
        }
    }

    $procExclusions = @('frxsvc.exe', 'frxccds.exe', 'frx.exe')
    foreach ($proc in $procExclusions) {
        $found = $prefs.ExclusionProcess | Where-Object { $_ -like "*$proc" }
        if ($found) {
            Add-Check 'Defender' "Process $proc" 'Pass' "$proc is excluded" $null
        } else {
            Add-Check 'Defender' "Process $proc" 'Warning' "$proc is NOT excluded from Defender" "Run: Add-MpPreference -ExclusionProcess '$proc'"
        }
    }

    if ($installPath) {
        $pathExcluded = $prefs.ExclusionPath | Where-Object { $_ -like "*FSLogix*" }
        if ($pathExcluded) {
            Add-Check 'Defender' 'FSLogix Path' 'Pass' 'FSLogix Apps path is excluded' $null
        } else {
            Add-Check 'Defender' 'FSLogix Path' 'Warning' 'FSLogix Apps path is NOT excluded from Defender' "Run: Add-MpPreference -ExclusionPath '$installPath'"
        }
    }
} catch {
    Add-Check 'Defender' 'Access' 'Info' 'Cannot read Defender preferences — may need admin rights or Defender may be disabled' $null
}

# ===== STORAGE ACCESSIBILITY =====
if ($profReg -and $profReg.VHDLocations) {
    $locations = @($profReg.VHDLocations)
    foreach ($loc in $locations) {
        if ($loc -and $loc.Trim()) {
            $locTrimmed = $loc.Trim()
            if (Test-Path -Path $locTrimmed) {
                Add-Check 'Storage' "Path: $locTrimmed" 'Pass' 'VHDLocations path is accessible' $null
            } else {
                Add-Check 'Storage' "Path: $locTrimmed" 'Fail' 'VHDLocations path is NOT accessible' 'Verify network connectivity, permissions, and DNS resolution'
            }
        }
    }
}

# ===== CLOUD CACHE =====
if ($ccdLocations) {
    Add-Check 'CloudCache' 'Configured' 'Pass' 'Cloud Cache CCDLocations is configured' $null
    
    # ClearCacheOnLogoff
    if ($profReg.ClearCacheOnLogoff -eq 1) {
        Add-Check 'CloudCache' 'ClearCacheOnLogoff' 'Pass' 'ClearCacheOnLogoff is enabled' $null
    } else {
        Add-Check 'CloudCache' 'ClearCacheOnLogoff' 'Warning' 'ClearCacheOnLogoff not enabled' 'Enable to save disk space on pooled session hosts'
    }

    # HealthyProvidersRequired
    if ($profReg.HealthyProvidersRequiredForRegister -ge 1) {
        Add-Check 'CloudCache' 'HealthyProviders' 'Pass' "HealthyProvidersRequiredForRegister: $($profReg.HealthyProvidersRequiredForRegister)" $null
    } else {
        Add-Check 'CloudCache' 'HealthyProviders' 'Warning' 'HealthyProvidersRequiredForRegister not set' 'Set to 1 to prevent login when no providers are healthy'
    }

    # Cache drive free space
    $cacheDrive = 'C:'
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$cacheDrive'" -ErrorAction SilentlyContinue
    if ($disk) {
        $freePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
        if ($freePercent -lt 10) {
            Add-Check 'CloudCache' 'Cache Drive Space' 'Fail' "Cache drive $cacheDrive has only ${freePercent}% free" 'Cloud Cache needs local disk space — clear cache or add storage'
        } elseif ($freePercent -lt 20) {
            Add-Check 'CloudCache' 'Cache Drive Space' 'Warning' "Cache drive $cacheDrive has ${freePercent}% free" 'Monitor disk space — Cloud Cache uses local storage'
        } else {
            Add-Check 'CloudCache' 'Cache Drive Space' 'Pass' "Cache drive $cacheDrive has ${freePercent}% free" $null
        }
    }
}

# ===== SUMMARY =====
$passCount = ($checks | Where-Object { $_.Status -eq 'Pass' }).Count
$warnCount = ($checks | Where-Object { $_.Status -eq 'Warning' }).Count
$failCount = ($checks | Where-Object { $_.Status -eq 'Fail' }).Count
$infoCount = ($checks | Where-Object { $_.Status -eq 'Info' }).Count
$total = $checks.Count

# Health score: 100 - (fails * 5) - (warnings * 2), min 0
$score = [math]::Max(0, 100 - ($failCount * 5) - ($warnCount * 2))

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    HealthScore  = $score
    Summary      = @{
        Total    = $total
        Pass     = $passCount
        Warning  = $warnCount
        Fail     = $failCount
        Info     = $infoCount
    }
    Checks       = $checks
}

$output | ConvertTo-Json -Depth 4
