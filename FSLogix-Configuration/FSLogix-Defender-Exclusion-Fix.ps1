# FSLogix: Defender Exclusion Fix
# Checks and applies FSLogix best-practice Microsoft Defender exclusions: .vhd/.vhdx/.cim extensions, FSLogix process exclusions, and Apps path exclusion. Reports what was missing and what was applied.
#Category: FSLogix: Configuration
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Defender Exclusion Audit & Fix — check and apply FSLogix best-practice exclusions.
.NOTES
    FleetCTRL Script Library | Category: Remediation & Repair
    Trigger: On-Demand / Boot | Admin Required: Yes | Destructive: No
#>
[CmdletBinding()]
param(
    [switch]$ApplyFix
)

$ErrorActionPreference = 'SilentlyContinue'

$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath

$requiredExtensions = @('.vhd', '.vhdx', '.cim')
$requiredProcesses = @('frxsvc.exe', 'frxccds.exe', 'frx.exe')
$requiredPaths = @()
if ($installPath) { $requiredPaths += $installPath }

$results = [System.Collections.ArrayList]::new()
$missingItems = [System.Collections.ArrayList]::new()

try {
    $prefs = Get-MpPreference -ErrorAction Stop
    
    # Extension exclusions
    foreach ($ext in $requiredExtensions) {
        $isExcluded = $prefs.ExclusionExtension -contains $ext
        [void]$results.Add(@{ Type = 'Extension'; Item = $ext; Excluded = $isExcluded })
        if (-not $isExcluded) { [void]$missingItems.Add(@{ Type = 'Extension'; Item = $ext }) }
    }
    
    # Process exclusions
    foreach ($proc in $requiredProcesses) {
        $isExcluded = [bool]($prefs.ExclusionProcess | Where-Object { $_ -like "*$proc" })
        [void]$results.Add(@{ Type = 'Process'; Item = $proc; Excluded = $isExcluded })
        if (-not $isExcluded) { [void]$missingItems.Add(@{ Type = 'Process'; Item = $proc }) }
    }
    
    # Path exclusions
    foreach ($p in $requiredPaths) {
        $isExcluded = [bool]($prefs.ExclusionPath | Where-Object { $_ -like "*FSLogix*" })
        [void]$results.Add(@{ Type = 'Path'; Item = $p; Excluded = $isExcluded })
        if (-not $isExcluded) { [void]$missingItems.Add(@{ Type = 'Path'; Item = $p }) }
    }
    
    # Apply fixes if requested
    $applied = [System.Collections.ArrayList]::new()
    if ($ApplyFix -and $missingItems.Count -gt 0) {
        $missingExts = ($missingItems | Where-Object { $_.Type -eq 'Extension' }).Item
        $missingProcs = ($missingItems | Where-Object { $_.Type -eq 'Process' }).Item
        $missingPaths = ($missingItems | Where-Object { $_.Type -eq 'Path' }).Item
        
        if ($missingExts) {
            try {
                Add-MpPreference -ExclusionExtension $missingExts -ErrorAction Stop
                [void]$applied.Add("Extensions: $($missingExts -join ', ')")
            } catch {
                [void]$applied.Add("FAILED to add extensions: $($_.Exception.Message)")
            }
        }
        if ($missingProcs) {
            try {
                Add-MpPreference -ExclusionProcess $missingProcs -ErrorAction Stop
                [void]$applied.Add("Processes: $($missingProcs -join ', ')")
            } catch {
                [void]$applied.Add("FAILED to add processes: $($_.Exception.Message)")
            }
        }
        if ($missingPaths) {
            try {
                Add-MpPreference -ExclusionPath $missingPaths -ErrorAction Stop
                [void]$applied.Add("Paths: $($missingPaths -join ', ')")
            } catch {
                [void]$applied.Add("FAILED to add paths: $($_.Exception.Message)")
            }
        }
    }
    
    $output = @{
        Timestamp      = [datetime]::UtcNow.ToString('o')
        ComputerName   = $env:COMPUTERNAME
        DefenderActive = $true
        AllExclusionsPresent = ($missingItems.Count -eq 0)
        MissingCount   = $missingItems.Count
        Results        = $results
        MissingItems   = $missingItems
        FixApplied     = $ApplyFix
        AppliedActions = $applied
    }
} catch {
    $output = @{
        Timestamp      = [datetime]::UtcNow.ToString('o')
        ComputerName   = $env:COMPUTERNAME
        DefenderActive = $false
        Error          = $_.Exception.Message
        Message        = 'Cannot read Defender preferences — Defender may be disabled or admin rights required'
    }
}

$output | ConvertTo-Json -Depth 3
