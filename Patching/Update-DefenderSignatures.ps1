# Update-DefenderSignatures
# Updates Windows Defender antivirus signatures via MpCmdRun.exe
#Category: Patching
#Run On: on_demand
#Timeout: 600
#Execution Mode: serial

<#
.SYNOPSIS
    Updates Windows Defender antivirus signatures.

.DESCRIPTION
    Invokes MpCmdRun.exe to trigger a signature definition update for
    Windows Defender. Uses exit codes from MpCmdRun.exe directly without
    parsing any localized text output.

.NOTES
    Log output: C:\ProgramData\Liquidware\FleetCTRL\Logs\
    Execution context: SYSTEM (Azure VM Run Command)
    Locale safety: COM objects and exit codes only - no localized text parsing
    FleetCTRL trigger: on_demand (primary), on_start (optional)

    Exit codes:
      0 = Success
      1 = General failure
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Log setup -----------------------------------------------------------
[string]$LogPath = "C:\ProgramData\Liquidware\FleetCTRL\Logs\DefenderUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    status                 = 'success'
    signature_version_before = $null
    signature_version_after  = $null
    error                  = $null
}

try {
    Write-FleetCTRLLog 'INFO' 'Starting Defender signature update'

    # Read current signature version via WMI (locale-safe).
    $defenderStatus = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' `
        -ClassName 'MSFT_MpComputerStatus' -ErrorAction SilentlyContinue
    if ($defenderStatus) {
        $result.signature_version_before = $defenderStatus.AntivirusSignatureVersion
        Write-FleetCTRLLog 'INFO' "Current signature version: $($defenderStatus.AntivirusSignatureVersion)"
    }

    # Locate MpCmdRun.exe.
    $mpCmdRun = "${env:ProgramFiles}\Windows Defender\MpCmdRun.exe"
    if (-not (Test-Path $mpCmdRun)) {
        $result.status = 'failed'
        $result.error  = 'MpCmdRun.exe not found'
        Write-FleetCTRLLog 'ERROR' $result.error
        $result | ConvertTo-Json -Depth 5
        exit 1
    }

    # Run signature update.
    Write-FleetCTRLLog 'INFO' 'Running MpCmdRun.exe -SignatureUpdate...'
    $proc = Start-Process -FilePath $mpCmdRun `
        -ArgumentList '-SignatureUpdate' `
        -Wait -PassThru -NoNewWindow

    Write-FleetCTRLLog 'INFO' "MpCmdRun exited with code: $($proc.ExitCode)"

    # Re-read signature version.
    $defenderStatusAfter = Get-CimInstance -Namespace 'root/Microsoft/Windows/Defender' `
        -ClassName 'MSFT_MpComputerStatus' -ErrorAction SilentlyContinue
    if ($defenderStatusAfter) {
        $result.signature_version_after = $defenderStatusAfter.AntivirusSignatureVersion
        Write-FleetCTRLLog 'INFO' "Signature version after: $($defenderStatusAfter.AntivirusSignatureVersion)"
    }

    # MpCmdRun exit code 0 = success, 2 = already up to date.
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 2) {
        $result.status = 'failed'
        $result.error  = "MpCmdRun exited with code $($proc.ExitCode)"
        Write-FleetCTRLLog 'ERROR' $result.error
        $result | ConvertTo-Json -Depth 5
        exit 1
    }

    Write-FleetCTRLLog 'INFO' 'Defender signature update completed successfully'
    $result | ConvertTo-Json -Depth 5
    exit 0

} catch {
    $result.status = 'failed'
    $result.error  = $_.Exception.Message
    Write-FleetCTRLLog 'ERROR' "Exception: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 5
    exit 1
}
