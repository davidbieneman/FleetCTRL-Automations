# FSLogix: App Masking Viewer
# Lists FSLogix App Masking rules (.fxr) and assignments (.fxa) from the Rules directory. Shows rule type, target path, action, and assignment targets (user, group, process).
#Category: FSLogix: Redirections
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    App Masking Rule Viewer — list FSLogix App Masking rules and assignments.
.DESCRIPTION
    Reads .fxr (rule) and .fxa (assignment) files from the FSLogix Rules directory.
    Parses XML content to show rule types, targets, actions, and assignments.
.NOTES
    FleetCTRL Script Library | Category: Redirections & App Masking
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
$rulesPath = $null

if ($installPath) {
    $candidate = Join-Path -Path $installPath -ChildPath 'Rules'
    if (Test-Path $candidate) { $rulesPath = $candidate }
}

# Also check common locations
if (-not $rulesPath) {
    $commonPaths = @(
        'C:\Program Files\FSLogix\Apps\Rules',
        "${env:ProgramFiles}\FSLogix\Apps\Rules"
    )
    foreach ($cp in $commonPaths) {
        if (Test-Path $cp) { $rulesPath = $cp; break }
    }
}

$rules = [System.Collections.ArrayList]::new()
$assignments = [System.Collections.ArrayList]::new()
$parseErrors = [System.Collections.ArrayList]::new()

if ($rulesPath -and (Test-Path $rulesPath)) {
    # Parse .fxr files (rules)
    $fxrFiles = Get-ChildItem -Path $rulesPath -Filter '*.fxr' -File -ErrorAction SilentlyContinue
    foreach ($fxr in $fxrFiles) {
        try {
            $content = Get-Content -Path $fxr.FullName -Raw -ErrorAction Stop
            # FXR files are binary with some readable sections
            # Try to extract meaningful info
            $ruleEntry = @{
                SourceFile = $fxr.Name
                SizeByte   = $fxr.Length
                LastModified = $fxr.LastWriteTimeUtc.ToString('o')
            }
            
            # Try XML parse first (some are XML-based)
            try {
                [xml]$xml = $content
                $ruleEntry['Format'] = 'XML'
                $ruleEntry['Parsed'] = $true
            } catch {
                # Binary format — extract what we can from readable strings
                $ruleEntry['Format'] = 'Binary'
                $ruleEntry['Parsed'] = $false
                
                # Extract readable paths from binary content
                $readableStrings = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($fxr.FullName)) -split "`0" |
                    Where-Object { $_ -match '^[A-Z]:\\|^HKLM|^HKCU|^\*\.' } |
                    Select-Object -Unique -First 10
                
                if ($readableStrings) {
                    $ruleEntry['TargetPaths'] = $readableStrings
                }
            }
            
            [void]$rules.Add($ruleEntry)
        } catch {
            [void]$parseErrors.Add(@{ File = $fxr.Name; Error = $_.Exception.Message })
        }
    }

    # Parse .fxa files (assignments)
    $fxaFiles = Get-ChildItem -Path $rulesPath -Filter '*.fxa' -File -ErrorAction SilentlyContinue
    foreach ($fxa in $fxaFiles) {
        try {
            $content = Get-Content -Path $fxa.FullName -Raw -ErrorAction Stop
            $assignEntry = @{
                SourceFile = $fxa.Name
                SizeByte   = $fxa.Length
                LastModified = $fxa.LastWriteTimeUtc.ToString('o')
            }
            
            try {
                [xml]$xml = $content
                $assignEntry['Format'] = 'XML'
                $assignEntry['Parsed'] = $true
            } catch {
                $assignEntry['Format'] = 'Binary'
                $assignEntry['Parsed'] = $false
                
                # Extract readable assignment targets
                $readableStrings = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($fxa.FullName)) -split "`0" |
                    Where-Object { $_ -match '^S-1-|^[A-Za-z]' -and $_.Length -gt 3 -and $_.Length -lt 200 } |
                    Select-Object -Unique -First 10
                
                if ($readableStrings) {
                    $assignEntry['AssignmentTargets'] = $readableStrings
                }
            }
            
            [void]$assignments.Add($assignEntry)
        } catch {
            [void]$parseErrors.Add(@{ File = $fxa.Name; Error = $_.Exception.Message })
        }
    }
}

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    RulesPath    = $rulesPath
    RulesPathExists = [bool]($rulesPath -and (Test-Path $rulesPath))
    Summary      = @{
        TotalRuleFiles      = $rules.Count
        TotalAssignmentFiles = $assignments.Count
        ParseErrors         = $parseErrors.Count
    }
    Rules        = $rules
    Assignments  = $assignments
    ParseErrors  = $parseErrors
}

$output | ConvertTo-Json -Depth 3
