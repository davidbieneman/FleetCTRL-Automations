# Install-M365Updates
# Triggers Microsoft 365 / Office Click-to-Run update
#Category: Patching
#Run On: on_demand
#Timeout: 1800
#Execution Mode: serial

<#
.SYNOPSIS
    Triggers Microsoft 365 / Office Click-to-Run update.

.DESCRIPTION
    Invokes the Office Click-to-Run (C2R) update mechanism to pull and apply
    the latest M365 Apps updates. Uses the OfficeC2RClient.exe binary which is
    present on all machines with Click-to-Run Office installed.

.NOTES
    Log output: C:\ProgramData\Liquidware\FleetCTRL\Logs\
    Execution context: SYSTEM (Azure VM Run Command)
    Locale safety: COM objects and exit codes only - no localized text parsing
    FleetCTRL trigger: on_demand (primary), on_start (optional)

    Exit codes:
      0 = Success (update applied or already current)
      1 = General failure
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Log setup -----------------------------------------------------------
[string]$LogPath = "C:\ProgramData\Liquidware\FleetCTRL\Logs\M365Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

function Write-FleetCTRLLog {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry
    Write-Output $entry
}

# ---- Main ----------------------------------------------------------------
$result = @{
    status          = 'success'
    c2r_path        = $null
    version_before  = $null
    version_after   = $null
    error           = $null
}

try {
    Write-FleetCTRLLog 'INFO' 'Starting M365/Office Click-to-Run update'

    # Locate Click-to-Run client.
    $c2rPath = "${env:CommonProgramFiles}\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
    if (-not (Test-Path $c2rPath)) {
        # Try 32-bit path on 64-bit OS.
        $c2rPath = "${env:CommonProgramFiles(x86)}\Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
    }

    if (-not (Test-Path $c2rPath)) {
        $result.status = 'skipped'
        $result.error  = 'Click-to-Run client not found; Office may not be installed via C2R'
        Write-FleetCTRLLog 'WARN' $result.error
        $result | ConvertTo-Json -Depth 5
        exit 0
    }

    $result.c2r_path = $c2rPath

    # Read current version from registry (locale-safe).
    $c2rReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($c2rReg -and $c2rReg.VersionToReport) {
        $result.version_before = $c2rReg.VersionToReport
        Write-FleetCTRLLog 'INFO' "Current version: $($c2rReg.VersionToReport)"
    }

    # Trigger update. The /update user flag triggers the update check + apply.
    # displaylevel=false suppresses any UI. forceappshutdown=true closes Office apps.
    Write-FleetCTRLLog 'INFO' 'Triggering C2R update...'
    $proc = Start-Process -FilePath $c2rPath `
        -ArgumentList '/update user displaylevel=false forceappshutdown=true' `
        -Wait -PassThru -NoNewWindow

    Write-FleetCTRLLog 'INFO' "C2R process exited with code: $($proc.ExitCode)"

    # Re-read version after update.
    $c2rRegAfter = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($c2rRegAfter -and $c2rRegAfter.VersionToReport) {
        $result.version_after = $c2rRegAfter.VersionToReport
        Write-FleetCTRLLog 'INFO' "Version after update: $($c2rRegAfter.VersionToReport)"
    }

    if ($proc.ExitCode -ne 0) {
        $result.status = 'failed'
        $result.error  = "C2R exited with code $($proc.ExitCode)"
        Write-FleetCTRLLog 'ERROR' $result.error
        $result | ConvertTo-Json -Depth 5
        exit 1
    }

    Write-FleetCTRLLog 'INFO' 'M365 update completed successfully'
    $result | ConvertTo-Json -Depth 5
    exit 0

} catch {
    $result.status = 'failed'
    $result.error  = $_.Exception.Message
    Write-FleetCTRLLog 'ERROR' "Exception: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 5
    exit 1
}
