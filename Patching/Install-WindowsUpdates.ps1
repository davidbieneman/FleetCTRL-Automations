# Install-WindowsUpdates
# Installs available Windows updates via the Windows Update COM API
#Category: Patching
#Run On: on_demand
#Timeout: 3600
#Execution Mode: serial

<#
.SYNOPSIS
    Installs available Windows updates via the Windows Update COM API.

.DESCRIPTION
    Searches for, downloads, and installs all applicable Windows updates using
    the native COM-based Windows Update Agent API. Does NOT parse any localized
    text output; all decisions are made via COM object properties and exit codes.

.NOTES
    Log output: C:\ProgramData\Liquidware\FleetCTRL\Logs\
    Execution context: SYSTEM (Azure VM Run Command)
    Locale safety: COM objects and exit codes only - no localized text parsing
    FleetCTRL trigger: on_demand (primary), on_start (optional)

    Exit codes:
      0    = Success, no reboot needed
      3001 = Success, reboot required to finish installation
      1    = General failure
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# ---- Log setup -----------------------------------------------------------
[string]$LogPath = "C:\ProgramData\Liquidware\FleetCTRL\Logs\WindowsUpdate_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
    status        = 'success'
    updates_found = 0
    installed     = @()
    failed        = @()
    reboot_needed = $false
    error         = $null
}

try {
    Write-FleetCTRLLog 'INFO' 'Starting Windows Update scan via COM API'

    $updateSession  = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()

    # Search for applicable, not-yet-installed updates.
    $searchResult = $updateSearcher.Search("IsInstalled=0 AND IsHidden=0")
    $result.updates_found = $searchResult.Updates.Count

    Write-FleetCTRLLog 'INFO' "Found $($searchResult.Updates.Count) update(s)"

    if ($searchResult.Updates.Count -eq 0) {
        Write-FleetCTRLLog 'INFO' 'No updates to install'
        $result | ConvertTo-Json -Depth 5
        exit 0
    }

    # Accept all EULAs and build download/install collections.
    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
    $updatesToInstall  = New-Object -ComObject Microsoft.Update.UpdateColl

    foreach ($update in $searchResult.Updates) {
        if (-not $update.EulaAccepted) {
            $update.AcceptEula()
        }
        $updatesToDownload.Add($update) | Out-Null
        $updatesToInstall.Add($update)  | Out-Null
        Write-FleetCTRLLog 'INFO' "Queued: $($update.Title)"
    }

    # Download updates.
    Write-FleetCTRLLog 'INFO' 'Downloading updates...'
    $downloader = $updateSession.CreateUpdateDownloader()
    $downloader.Updates = $updatesToDownload
    $downloadResult = $downloader.Download()
    Write-FleetCTRLLog 'INFO' "Download result code: $($downloadResult.ResultCode)"

    # Install updates.
    Write-FleetCTRLLog 'INFO' 'Installing updates...'
    $installer = $updateSession.CreateUpdateInstaller()
    $installer.Updates = $updatesToInstall
    $installResult = $installer.Install()

    for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
        $update    = $updatesToInstall.Item($i)
        $perResult = $installResult.GetUpdateResult($i)
        # ResultCode: 2 = Succeeded, 3 = Succeeded with errors, 4 = Failed, 5 = Aborted
        if ($perResult.ResultCode -ge 2 -and $perResult.ResultCode -le 3) {
            $result.installed += $update.Title
            Write-FleetCTRLLog 'INFO' "Installed: $($update.Title)"
        } else {
            $result.failed += $update.Title
            Write-FleetCTRLLog 'WARN' "Failed: $($update.Title) (code $($perResult.ResultCode))"
        }
    }

    # Check overall reboot requirement (COM property, not localized text).
    $result.reboot_needed = $installResult.RebootRequired

    if ($result.failed.Count -gt 0) {
        $result.status = 'partial'
        Write-FleetCTRLLog 'WARN' "$($result.failed.Count) update(s) failed"
    }

    Write-FleetCTRLLog 'INFO' "Completed: $($result.installed.Count) installed, $($result.failed.Count) failed, reboot=$($result.reboot_needed)"

    $result | ConvertTo-Json -Depth 5

    if ($result.reboot_needed) {
        exit 3001
    }
    exit 0

} catch {
    $result.status = 'failed'
    $result.error  = $_.Exception.Message
    Write-FleetCTRLLog 'ERROR' "Exception: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 5
    exit 1
}
