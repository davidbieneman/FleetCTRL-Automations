# Send-LogoffWarning
# Sends a toast/WTS warning message to all connected user sessions
#Category: Maintenance
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

<#
.SYNOPSIS
    Sends a logoff warning message to all connected user sessions.

.DESCRIPTION
    Enumerates active user sessions via the Win32 WTS API and sends a
    warning message to each connected session. Uses WTSSendMessage for
    reliable message delivery without parsing any localized text.

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
param(
    [string]$Title   = 'Scheduled Maintenance',
    [string]$Message = 'This machine will undergo scheduled maintenance shortly. Please save your work and log off.',
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Stop'

# ---- Log setup -----------------------------------------------------------
[string]$LogPath = "C:\ProgramData\Liquidware\FleetCTRL\Logs\LogoffWarning_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

function Write-FleetCTRLLog {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $LogPath -Value $entry
    Write-Output $entry
}

# ---- WTS API via P/Invoke -----------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WtsApi {
    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern IntPtr WTSOpenServer(string pServerName);

    [DllImport("wtsapi32.dll")]
    public static extern void WTSCloseServer(IntPtr hServer);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSEnumerateSessions(
        IntPtr hServer, int Reserved, int Version,
        out IntPtr ppSessionInfo, out int pCount);

    [DllImport("wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool WTSSendMessage(
        IntPtr hServer, int SessionId, string pTitle, int TitleLength,
        string pMessage, int MessageLength, int Style, int Timeout,
        out int pResponse, bool bWait);

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO {
        public int SessionId;
        [MarshalAs(UnmanagedType.LPStr)]
        public string pWinStationName;
        public int State;
    }
}
"@ -ErrorAction SilentlyContinue

# ---- Main ----------------------------------------------------------------
$result = @{
    status         = 'success'
    sessions_found = 0
    messages_sent  = 0
    messages_failed = 0
    error          = $null
}

try {
    Write-FleetCTRLLog 'INFO' "Sending logoff warning: '$Title' to all active sessions"

    $hServer = [WtsApi]::WTSOpenServer($env:COMPUTERNAME)
    $ppSessionInfo = [IntPtr]::Zero
    $sessionCount  = 0

    $enumOk = [WtsApi]::WTSEnumerateSessions($hServer, 0, 1, [ref]$ppSessionInfo, [ref]$sessionCount)
    if (-not $enumOk) {
        throw "WTSEnumerateSessions failed (Win32 error: $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
    }

    $structSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][WtsApi+WTS_SESSION_INFO])
    $activeSessions = @()

    for ($i = 0; $i -lt $sessionCount; $i++) {
        $ptr = [IntPtr]::Add($ppSessionInfo, $i * $structSize)
        $sessionInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][WtsApi+WTS_SESSION_INFO])

        # State 0 = Active (WTSActive)
        if ($sessionInfo.State -eq 0 -and $sessionInfo.SessionId -gt 0) {
            $activeSessions += $sessionInfo
        }
    }

    [WtsApi]::WTSFreeMemory($ppSessionInfo)
    $result.sessions_found = $activeSessions.Count

    Write-FleetCTRLLog 'INFO' "Found $($activeSessions.Count) active session(s)"

    foreach ($sess in $activeSessions) {
        $response = 0
        $titleBytes   = [System.Text.Encoding]::Unicode.GetByteCount($Title)
        $messageBytes = [System.Text.Encoding]::Unicode.GetByteCount($Message)

        $sendOk = [WtsApi]::WTSSendMessage(
            $hServer,
            $sess.SessionId,
            $Title,
            $titleBytes,
            $Message,
            $messageBytes,
            0x00000040,     # MB_ICONINFORMATION
            $TimeoutSec,
            [ref]$response,
            $false          # don't wait for user response
        )

        if ($sendOk) {
            $result.messages_sent++
            Write-FleetCTRLLog 'INFO' "Message sent to session $($sess.SessionId)"
        } else {
            $result.messages_failed++
            $win32Err = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-FleetCTRLLog 'WARN' "Failed to send to session $($sess.SessionId) (Win32 error: $win32Err)"
        }
    }

    [WtsApi]::WTSCloseServer($hServer)

    if ($result.messages_failed -gt 0 -and $result.messages_sent -eq 0) {
        $result.status = 'failed'
        $result.error  = 'Failed to send any messages'
        Write-FleetCTRLLog 'ERROR' $result.error
    }

    Write-FleetCTRLLog 'INFO' "Completed: $($result.messages_sent) sent, $($result.messages_failed) failed"
    $result | ConvertTo-Json -Depth 5

    if ($result.status -eq 'failed') { exit 1 }
    exit 0

} catch {
    $result.status = 'failed'
    $result.error  = $_.Exception.Message
    Write-FleetCTRLLog 'ERROR' "Exception: $($_.Exception.Message)"
    $result | ConvertTo-Json -Depth 5
    exit 1
}
