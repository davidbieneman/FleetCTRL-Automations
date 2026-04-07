# FSLogix: Cloud Cache Validator
# Parses and validates CCDLocations string syntax (case-sensitive!), tests provider accessibility, checks for VHDLocations/CCDLocations conflicts, and validates supporting settings.
#Category: FSLogix: Cloud Cache
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Cloud Cache Config Validator — parse and validate CCDLocations string.
.NOTES
    FleetCTRL Script Library | Category: Cloud Cache
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$ccdRaw = $profReg.CCDLocations
$vhdLoc = $profReg.VHDLocations

$checks = [System.Collections.ArrayList]::new()

if (-not $ccdRaw) {
    @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        CloudCacheConfigured = $false
        Message = 'No CCDLocations configured'
    } | ConvertTo-Json -Depth 2
    return
}

# Parse CCDLocations string
# Format: type=smb,name="NAME",connectionString=\\path;type=azure,...
$providers = [System.Collections.ArrayList]::new()
$segments = $ccdRaw -split ';'

foreach ($seg in $segments) {
    $seg = $seg.Trim()
    if (-not $seg) { continue }
    
    $prov = @{ Raw = $seg }
    
    # Extract type
    if ($seg -match 'type=(\w+)') { $prov['Type'] = $Matches[1] }
    # Extract name
    if ($seg -match 'name="?([^",]+)"?') { $prov['Name'] = $Matches[1] }
    # Extract connectionString
    if ($seg -match 'connectionString="?([^"]+)"?$') { $prov['ConnectionString'] = $Matches[1] }
    elseif ($seg -match 'connectionString=(.+)$') { $prov['ConnectionString'] = $Matches[1] }
    
    # Validate
    $prov['IsValid'] = [bool]($prov['Type'] -and $prov['ConnectionString'])
    
    # Case sensitivity check
    if ($seg -cmatch 'Type=' -or $seg -cmatch 'ConnectionString=' -or $seg -cmatch 'Name=') {
        $prov['CaseSensitivityWarning'] = 'CCDLocations is CASE SENSITIVE — use lowercase: type=, name=, connectionString='
        [void]$checks.Add(@{ Level = 'Warning'; Check = 'CaseSensitivity'; Message = "Provider '$($prov['Name'])': CCDLocations keys must be lowercase (type=, not Type=)" })
    }
    
    # Test SMB accessibility
    if ($prov['Type'] -eq 'smb' -and $prov['ConnectionString']) {
        $connStr = $prov['ConnectionString']
        if (Test-Path -Path $connStr) {
            $prov['Accessible'] = $true
            [void]$checks.Add(@{ Level = 'Pass'; Check = "SMB_$($prov['Name'])"; Message = "SMB path accessible: $connStr" })
        } else {
            $prov['Accessible'] = $false
            [void]$checks.Add(@{ Level = 'Fail'; Check = "SMB_$($prov['Name'])"; Message = "SMB path NOT accessible: $connStr" })
        }
    }
    
    [void]$providers.Add($prov)
}

# Provider count check
if ($providers.Count -gt 4) {
    [void]$checks.Add(@{ Level = 'Warning'; Check = 'ProviderCount'; Message = "Found $($providers.Count) providers — maximum recommended is 4" })
} elseif ($providers.Count -eq 0) {
    [void]$checks.Add(@{ Level = 'Fail'; Check = 'ProviderCount'; Message = 'No valid providers parsed from CCDLocations' })
} else {
    [void]$checks.Add(@{ Level = 'Pass'; Check = 'ProviderCount'; Message = "$($providers.Count) provider(s) configured" })
}

# VHDLocations conflict
if ($vhdLoc) {
    [void]$checks.Add(@{ Level = 'Warning'; Check = 'VHDLocationsConflict'; Message = 'Both VHDLocations AND CCDLocations are set — FSLogix should use only one' })
}

# Supporting settings
$clearCache = $profReg.ClearCacheOnLogoff
$healthyReq = $profReg.HealthyProvidersRequiredForRegister

if ($clearCache -eq 1) {
    [void]$checks.Add(@{ Level = 'Pass'; Check = 'ClearCacheOnLogoff'; Message = 'ClearCacheOnLogoff is enabled' })
} else {
    [void]$checks.Add(@{ Level = 'Warning'; Check = 'ClearCacheOnLogoff'; Message = 'ClearCacheOnLogoff not enabled — recommended for pooled hosts' })
}

if ($healthyReq -ge 1) {
    [void]$checks.Add(@{ Level = 'Pass'; Check = 'HealthyProviders'; Message = "HealthyProvidersRequiredForRegister: $healthyReq" })
} else {
    [void]$checks.Add(@{ Level = 'Warning'; Check = 'HealthyProviders'; Message = 'HealthyProvidersRequiredForRegister not set — users may login with no healthy providers' })
}

# FSLogix version check for Cloud Cache support
$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
if ($installPath) {
    $frxExe = Join-Path -Path $installPath -ChildPath 'frxsvc.exe'
    if (Test-Path $frxExe) {
        $ver = (Get-Item $frxExe).VersionInfo
        [void]$checks.Add(@{ Level = 'Info'; Check = 'FSLogixVersion'; Message = "FSLogix version: $($ver.FileVersion)" })
    }
}

$output = @{
    Timestamp        = [datetime]::UtcNow.ToString('o')
    ComputerName     = $env:COMPUTERNAME
    CCDLocationsRaw  = $ccdRaw
    ProviderCount    = $providers.Count
    Providers        = $providers
    Checks           = $checks
}

$output | ConvertTo-Json -Depth 4
