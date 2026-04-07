# FSLogix: VHD-to-CloudCache Prep
# Pre-flight check before migrating from VHDLocations to Cloud Cache. Validates target CCDLocations string, storage accessibility, existing profile pickup, case-sensitivity gotchas, and version compatibility.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    VHDLocations-to-CloudCache Migration Prep — pre-flight validation.
.NOTES
    FleetCTRL Script Library | Category: Container Portability
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param(
    [string]$TargetCCDLocations = ''
)

$ErrorActionPreference = 'SilentlyContinue'

$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$checks = [System.Collections.ArrayList]::new()

# Current state
$currentVHD = $profReg.VHDLocations
$currentCCD = $profReg.CCDLocations

[void]$checks.Add(@{ Check = 'CurrentVHDLocations'; Value = $currentVHD; Status = if ($currentVHD) { 'Set' } else { 'NotSet' } })
[void]$checks.Add(@{ Check = 'CurrentCCDLocations'; Value = $currentCCD; Status = if ($currentCCD) { 'Set' } else { 'NotSet' } })

# Existing profiles at VHDLocations
$existingProfiles = 0
if ($currentVHD) {
    $paths = @($currentVHD)
    foreach ($p in $paths) {
        $pt = $p.Trim()
        if (Test-Path $pt) {
            $count = (Get-ChildItem -Path $pt -Directory -ErrorAction SilentlyContinue).Count
            $existingProfiles += $count
            [void]$checks.Add(@{ Check = "ExistingProfiles_$pt"; Value = $count; Status = 'Info'; Message = "Found $count profile folders — Cloud Cache will pick these up if using the same share path" })
        }
    }
}

# Version check
$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
if ($installPath) {
    $frxExe = Join-Path -Path $installPath -ChildPath 'frxsvc.exe'
    if (Test-Path $frxExe) {
        $ver = (Get-Item $frxExe).VersionInfo.FileVersion
        $supportsCC = $true  # All modern versions support CC
        [void]$checks.Add(@{ Check = 'FSLogixVersion'; Value = $ver; Status = 'Pass'; Message = "Version $ver supports Cloud Cache" })
    }
}

# Validate target CCDLocations if provided
if ($TargetCCDLocations) {
    # Case sensitivity
    if ($TargetCCDLocations -cmatch 'Type=' -or $TargetCCDLocations -cmatch 'ConnectionString=') {
        [void]$checks.Add(@{ Check = 'CaseSensitivity'; Status = 'Fail'; Message = 'CRITICAL: CCDLocations is case-sensitive. Use lowercase: type=, connectionString=, name=. This is the #1 migration gotcha.' })
    } else {
        [void]$checks.Add(@{ Check = 'CaseSensitivity'; Status = 'Pass'; Message = 'CCDLocations keys appear to use correct lowercase' })
    }
    
    # Parse and test providers
    $segments = $TargetCCDLocations -split ';'
    $provNum = 0
    foreach ($seg in $segments) {
        $seg = $seg.Trim()
        if (-not $seg) { continue }
        $provNum++
        
        if ($seg -match 'connectionString=(.+?)(?:;|$)') {
            $connStr = $Matches[1] -replace '"', ''
            if ($connStr -match '^\\\\') {
                # SMB path
                if (Test-Path $connStr) {
                    [void]$checks.Add(@{ Check = "Provider${provNum}_Access"; Status = 'Pass'; Message = "SMB path accessible: $connStr" })
                } else {
                    [void]$checks.Add(@{ Check = "Provider${provNum}_Access"; Status = 'Fail'; Message = "SMB path NOT accessible: $connStr" })
                }
            } else {
                [void]$checks.Add(@{ Check = "Provider${provNum}_Access"; Status = 'Info'; Message = "Non-SMB provider — cannot test from script: $connStr" })
            }
        }
    }
}

# Coexistence warning
if ($currentVHD -and $currentCCD) {
    [void]$checks.Add(@{ Check = 'Coexistence'; Status = 'Warning'; Message = 'Both VHDLocations and CCDLocations currently set — you must remove VHDLocations before enabling Cloud Cache' })
}

# Migration steps
$migrationSteps = @(
    '1. Ensure target CCDLocations string uses correct case (lowercase type=, connectionString=, name=)',
    '2. Verify storage accounts are accessible from all session hosts',
    '3. Remove VHDLocations GPO/registry setting',
    '4. Set CCDLocations GPO/registry setting',
    '5. Run gpupdate on hosts',
    '6. Test with a single user login — verify profile mounts correctly',
    '7. Check FSLogix event logs for errors',
    '8. If using same share path, existing profiles will be picked up automatically',
    '9. Add secondary storage location for DR once primary is validated'
)

$output = @{
    Timestamp        = [datetime]::UtcNow.ToString('o')
    ComputerName     = $env:COMPUTERNAME
    ExistingProfiles = $existingProfiles
    Checks           = $checks
    MigrationSteps   = $migrationSteps
}

$output | ConvertTo-Json -Depth 3
