# Logoff Disconnected Sessions
# Force logoff all DISCONNECTED sessions only. Active sessions are never touched. Use before maintenance or agent repair.
#Category: Sessions
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

# Use WTS API to enumerate sessions — locale-safe (no parsing localized text).
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class WtsSession {
    public const int WTS_CURRENT_SERVER_HANDLE = 0;
    public const int WTSDisconnected = 4;

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO {
        public int SessionId;
        [MarshalAs(UnmanagedType.LPStr)] public string pWinStationName;
        public int State;
    }

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version,
        out IntPtr ppSessionInfo, out int pCount);

    [DllImport("wtsapi32.dll")]
    public static extern void WTSFreeMemory(IntPtr pMemory);

    [DllImport("wtsapi32.dll", SetLastError = true)]
    public static extern bool WTSLogoffSession(IntPtr hServer, int sessionId, bool bWait);
}
"@

$loggedOff = 0
$skipped = 0
$ppSessionInfo = [IntPtr]::Zero
$count = 0

if ([WtsSession]::WTSEnumerateSessions([IntPtr]::Zero, 0, 1, [ref]$ppSessionInfo, [ref]$count)) {
    $structSize = [Runtime.InteropServices.Marshal]::SizeOf([type][WtsSession+WTS_SESSION_INFO])
    for ($i = 0; $i -lt $count; $i++) {
        $ptr = [IntPtr]($ppSessionInfo.ToInt64() + ($i * $structSize))
        $si = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][WtsSession+WTS_SESSION_INFO])

        if ($si.SessionId -le 0) { continue }  # skip services session

        if ($si.State -eq [WtsSession]::WTSDisconnected) {
            [WtsSession]::WTSLogoffSession([IntPtr]::Zero, $si.SessionId, $false) | Out-Null
            $loggedOff++
        } else {
            $skipped++
        }
    }
    [WtsSession]::WTSFreeMemory($ppSessionInfo)
}

@{ success = $true; disconnected_logged_off = $loggedOff; active_skipped = $skipped } | ConvertTo-Json
