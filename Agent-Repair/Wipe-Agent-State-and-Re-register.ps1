# Wipe Agent State and Re-register
# Nuclear option: deletes BOTH registry hives entirely, recreates with clean state. Use when re-register fails due to corrupted hive.
#Category: Agent Repair
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -RunAsAdministrator
param([Parameter(Mandatory)][string]$RegistrationToken)
$ErrorActionPreference = 'Stop'

Stop-Service -Name 'RDAgentBootLoader' -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'RdAgent' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Remove-Item 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'      -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader' -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -Force | Out-Null
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -Name 'RegistrationToken' -Value $RegistrationToken -Force
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -Name 'IsRegistered'      -Value 0                  -Force

Start-Service -Name 'RdAgent'
Start-Sleep -Seconds 3
Start-Service -Name 'RDAgentBootLoader'
Start-Sleep -Seconds 10

$reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
@{
    success       = ($reg.IsRegistered -eq 1)
    is_registered = $reg.IsRegistered
} | ConvertTo-Json