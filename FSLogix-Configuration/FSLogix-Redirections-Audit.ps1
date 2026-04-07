# FSLogix: Redirections Audit
# Reads current redirections.xml, lists all exclusions/inclusions, and compares against best-practice template. Flags missing recommended exclusions for Teams, browser caches, etc.
#Category: FSLogix: Configuration
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    Redirections.xml Audit — read current config and compare against best practices.
.NOTES
    FleetCTRL Script Library | Category: Redirections & App Masking
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# Find redirections.xml
$redirFolder = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -Name 'RedirXMLSourceFolder' -ErrorAction SilentlyContinue).RedirXMLSourceFolder
$xmlPath = $null
$xmlContent = $null

if ($redirFolder) {
    $candidate = Join-Path -Path $redirFolder -ChildPath 'Redirections.xml'
    if (Test-Path $candidate) { $xmlPath = $candidate }
}

# Also check common locations
if (-not $xmlPath) {
    $commonPaths = @(
        'C:\ProgramData\FSLogix\Redirections.xml',
        'C:\Program Files\FSLogix\Apps\Redirections.xml'
    )
    foreach ($cp in $commonPaths) {
        if (Test-Path $cp) { $xmlPath = $cp; break }
    }
}

$currentExcludes = [System.Collections.ArrayList]::new()
$currentIncludes = [System.Collections.ArrayList]::new()

if ($xmlPath) {
    try {
        [xml]$xml = Get-Content -Path $xmlPath -ErrorAction Stop
        
        foreach ($excl in $xml.FrxProfileFolderRedirection.Excludes.Exclude) {
            [void]$currentExcludes.Add(@{
                Path = $excl.'#text'
                Copy = $excl.Copy
            })
        }
        foreach ($incl in $xml.FrxProfileFolderRedirection.Includes.Include) {
            [void]$currentIncludes.Add(@{
                Path = $incl.'#text'
                Copy = $incl.Copy
            })
        }
    } catch {
        # XML parse error
    }
}

# Recommended exclusions to check against
$recommended = @(
    @{ Path = 'AppData\Local\CrashDumps'; Category = 'Windows' }
    @{ Path = 'AppData\Local\Google\Chrome\User Data\Default\Cache'; Category = 'Browser' }
    @{ Path = 'AppData\Local\Microsoft\Edge\User Data\Default\Cache'; Category = 'Browser' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\media-stack'; Category = 'Teams Classic' }
    @{ Path = 'AppData\Roaming\Microsoft\Teams\Service Worker'; Category = 'Teams Classic' }
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\Logs'; Category = 'New Teams' }
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\PerfLogs'; Category = 'New Teams' }
    @{ Path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView\WV2Profile_tfw\GPUCache'; Category = 'New Teams' }
    @{ Path = 'AppData\Local\Microsoft\olk\logs'; Category = 'New Outlook' }
    @{ Path = 'AppData\Local\Microsoft\Terminal Server Client\Cache'; Category = 'RDP' }
)

$missing = [System.Collections.ArrayList]::new()
$currentPaths = $currentExcludes | ForEach-Object { $_.Path }

foreach ($rec in $recommended) {
    $found = $currentPaths | Where-Object { $_ -eq $rec.Path }
    if (-not $found) {
        [void]$missing.Add($rec)
    }
}

$output = @{
    Timestamp        = [datetime]::UtcNow.ToString('o')
    ComputerName     = $env:COMPUTERNAME
    RedirXMLSource   = $redirFolder
    XmlPath          = $xmlPath
    XmlFound         = [bool]$xmlPath
    Summary          = @{
        TotalExclusions      = $currentExcludes.Count
        TotalInclusions      = $currentIncludes.Count
        MissingRecommended   = $missing.Count
        RecommendedChecked   = $recommended.Count
    }
    CurrentExclusions = $currentExcludes
    CurrentInclusions = $currentIncludes
    MissingRecommended = $missing
}

$output | ConvertTo-Json -Depth 3
