# Check Pending Reboot (Windows Update)
# Detects pending reboots from Windows Update, CBS, or component servicing that block AVD agent updates. Reports status only.
#Category: Environment
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$pending = $false
$reasons = @()

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $pending = $true; $reasons += 'CBS_RebootPending'
}
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $pending = $true; $reasons += 'WU_RebootRequired'
}
$pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue).PendingFileRenameOperations
if ($pfro) { $pending = $true; $reasons += 'PendingFileRename' }
try {
    $sccm = Invoke-CimMethod -Namespace 'root\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending'
    if ($sccm.RebootPending -or $sccm.IsHardRebootPending) { $pending = $true; $reasons += 'SCCM_RebootPending' }
} catch { }

@{
    success        = $true
    reboot_pending = $pending
    reasons        = $reasons
    action         = if ($pending) { 'schedule_reboot' } else { 'none' }
} | ConvertTo-Json