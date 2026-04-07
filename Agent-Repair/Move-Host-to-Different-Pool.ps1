# Move Host to Different Pool
# Moves a session host between pools without reimaging. Same as re-register but FleetCTRL passes the TARGET pool's token.
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

$path = 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
Set-ItemProperty -Path $path -Name 'RegistrationToken' -Value $RegistrationToken -Force
Set-ItemProperty -Path $path -Name 'IsRegistered'      -Value 0                  -Force

Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader' -Recurse -Force -ErrorAction SilentlyContinue

Start-Service -Name 'RdAgent' -ErrorAction Stop
Start-Sleep -Seconds 3
Start-Service -Name 'RDAgentBootLoader' -ErrorAction Stop
Start-Sleep -Seconds 10

$reg = Get-ItemProperty -Path $path
@{
    success       = ($reg.IsRegistered -eq 1 -and [string]::IsNullOrEmpty($reg.RegistrationToken))
    is_registered = $reg.IsRegistered
    token_cleared = [string]::IsNullOrEmpty($reg.RegistrationToken)
} | ConvertTo-Json