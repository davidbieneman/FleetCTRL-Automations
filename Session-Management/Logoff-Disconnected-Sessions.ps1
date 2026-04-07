# Logoff Disconnected Sessions
# Force logoff all DISCONNECTED sessions only. Active sessions are never touched. Use before maintenance or agent repair.
#Category: Session Management
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$quserOut = & quser 2>$null
$loggedOff = 0
$skipped = 0

if ($quserOut) {
    foreach ($line in $quserOut[1..($quserOut.Length - 1)]) {
        if ($line -match 'Disc') {
            if ($line -match '\s+(\d+)\s+Disc') {
                $sessionId = $Matches[1]
                & logoff $sessionId /server:localhost 2>$null
                $loggedOff++
            }
        } else {
            $skipped++
        }
    }
}

@{ success = $true; disconnected_logged_off = $loggedOff; active_skipped = $skipped } | ConvertTo-Json