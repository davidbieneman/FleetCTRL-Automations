# FSLogix: Cross-Platform Readiness
# Validates that FSLogix config supports profile roaming between AVD and Windows 365 via Cloud Cache. Checks CCDLocations, identity type, naming conventions, and ODFC parity. Returns readiness score.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Cross-Platform Profile Sharing Readiness — AVD ↔ Windows 365 validation.
.DESCRIPTION
    Validates FSLogix config supports profile roaming between AVD and W365
    via Cloud Cache. Returns readiness score with specific remediation items.
.NOTES
    FleetCTRL Script Library | Category: Container Portability
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$odfcReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\ODFC' -ErrorAction SilentlyContinue

$checks = [System.Collections.ArrayList]::new()
$maxScore = 0
$earnedScore = 0

function Add-ReadinessCheck {
    param([string]$Name, [bool]$Passed, [string]$Message, [string]$Remediation, [int]$Weight = 10)
    $script:maxScore += $Weight
    if ($Passed) { $script:earnedScore += $Weight }
    [void]$script:checks.Add(@{
        Name        = $Name
        Passed      = $Passed
        Weight      = $Weight
        Message     = $Message
        Remediation = if (-not $Passed) { $Remediation } else { $null }
    })
}

# 1. Cloud Cache enabled (most critical)
$ccdEnabled = [bool]$profReg.CCDLocations
Add-ReadinessCheck 'Cloud Cache Enabled' $ccdEnabled `
    $(if ($ccdEnabled) { 'CCDLocations is configured — Cloud Cache is the mechanism for cross-platform sharing' } else { 'CCDLocations not configured — VHDLocations alone cannot share between AVD and W365' }) `
    'Configure CCDLocations with shared storage accessible from both AVD and W365' 20

# 2. No VHDLocations conflict
$noConflict = -not ($profReg.VHDLocations -and $profReg.CCDLocations)
Add-ReadinessCheck 'No Storage Conflict' $noConflict `
    $(if ($noConflict) { 'Only one storage method configured' } else { 'Both VHDLocations AND CCDLocations set' }) `
    'Remove VHDLocations when using Cloud Cache' 15

# 3. FlipFlop naming
$flipFlop = $profReg.FlipFlopProfileDirectoryName -eq 1
Add-ReadinessCheck 'FlipFlop Naming' $flipFlop `
    $(if ($flipFlop) { 'Consistent folder naming enabled' } else { 'FlipFlop not enabled' }) `
    'Enable FlipFlopProfileDirectoryName=1 for consistent naming across platforms' 10

# 4. Identity type (Entra ID preferred for cross-platform)
$sessions = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles\Sessions\*' -ErrorAction SilentlyContinue
$hasEntraId = $false
if ($sessions) {
    foreach ($s in $sessions) {
        if ($s.PSChildName -match '^S-1-12-1-') { $hasEntraId = $true; break }
    }
}
Add-ReadinessCheck 'Entra ID Identity' $hasEntraId `
    $(if ($hasEntraId) { 'Entra ID identities detected — works across AVD and W365' } else { 'No active Entra ID sessions detected (AD DS SIDs may not roam to W365)' }) `
    'Ensure users have Entra ID (S-1-12-1-*) identities for cross-platform roaming' 15

# 5. ClearCacheOnLogoff
$clearCache = $profReg.ClearCacheOnLogoff -eq 1
Add-ReadinessCheck 'Clear Cache on Logoff' $clearCache `
    $(if ($clearCache) { 'Local cache cleared on logoff — prevents stale data between platforms' } else { 'Local cache retained — risk of stale data when switching platforms' }) `
    'Enable ClearCacheOnLogoff=1 for pooled/shared environments' 10

# 6. Single container mode
$singleContainer = ($profReg.Enabled -eq 1 -and (-not $odfcReg -or $odfcReg.Enabled -ne 1))
Add-ReadinessCheck 'Single Container Mode' $singleContainer `
    $(if ($singleContainer) { 'Using single container — simplifies cross-platform roaming' } else { 'Dual container mode — ensure ODFC has matching CCDLocations' }) `
    'Microsoft recommends single-container (Profile Container only) for cross-platform' 10

# 7. DeleteLocalProfile
$deletLocal = $profReg.DeleteLocalProfileWhenVHDShouldApply -eq 1
Add-ReadinessCheck 'Delete Local Profile' $deletLocal `
    $(if ($deletLocal) { 'Local profiles cleaned up on apply' } else { 'Local profiles may persist and conflict' }) `
    'Enable DeleteLocalProfileWhenVHDShouldApply=1' 10

# 8. HealthyProviders
$healthyProv = $profReg.HealthyProvidersRequiredForRegister -ge 1
Add-ReadinessCheck 'Healthy Providers Required' $healthyProv `
    $(if ($healthyProv) { "Requires $($profReg.HealthyProvidersRequiredForRegister) healthy provider(s)" } else { 'No minimum healthy providers — users may login with no storage' }) `
    'Set HealthyProvidersRequiredForRegister=1' 10

# Score
$readinessPercent = if ($maxScore -gt 0) { [math]::Round(($earnedScore / $maxScore) * 100, 0) } else { 0 }

$output = @{
    Timestamp        = [datetime]::UtcNow.ToString('o')
    ComputerName     = $env:COMPUTERNAME
    ReadinessScore   = $readinessPercent
    ReadinessGrade   = switch ($readinessPercent) {
        { $_ -ge 90 } { 'Ready' }
        { $_ -ge 70 } { 'Mostly Ready' }
        { $_ -ge 50 } { 'Needs Work' }
        default        { 'Not Ready' }
    }
    MaxScore         = $maxScore
    EarnedScore      = $earnedScore
    Checks           = $checks
}

$output | ConvertTo-Json -Depth 3
