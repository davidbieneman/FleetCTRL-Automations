# FSLogix: Clear Orphaned Local Profiles
# Removes orphaned local user profiles from pooled session hosts. Frees disk eaten by failed FSLogix mounts. ONLY run in drain mode with zero sessions.
#Category: FSLogix
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$activeSessions = @(Get-CimInstance -ClassName Win32_LogonSession | Where-Object { $_.LogonType -eq 10 }).Count
if ($activeSessions -gt 0) {
    @{ success = $false; error = 'active_sessions_present'; count = $activeSessions } | ConvertTo-Json
    exit 1
}

$profiles = Get-CimInstance -ClassName Win32_UserProfile |
    Where-Object { -not $_.Special -and $_.LocalPath -notlike "*$env:SystemRoot*" -and $_.LocalPath -notlike "*\Default*" -and $_.LocalPath -notlike "*\Public*" }

$removed = 0
foreach ($p in $profiles) {
    try {
        $p | Remove-CimInstance -ErrorAction Stop
        $removed++
    } catch { }
}

@{ success = $true; profiles_removed = $removed } | ConvertTo-Json