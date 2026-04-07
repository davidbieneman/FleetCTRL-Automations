# Set Agent Delayed Auto-Start
# Sets RDAgentBootLoader to Delayed Auto start. Prevents boot-race condition where agent loses to other services. MS documented fix for hosts unhealthy after every reboot.
#Category: Soft Fix
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Set-Service -Name 'RDAgentBootLoader' -StartupType AutomaticDelayedStart
sc.exe config 'RDAgentBootLoader' start= delayed-auto | Out-Null

$timeoutMs = 60000
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'ServicesPipeTimeout' -Value $timeoutMs -PropertyType DWORD -Force | Out-Null

@{ success = $true; startup_type = 'AutomaticDelayedStart'; timeout_ms = $timeoutMs } | ConvertTo-Json