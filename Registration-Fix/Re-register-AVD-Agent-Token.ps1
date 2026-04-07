# Re-register AVD Agent (Token)
# Resets IsRegistered to 0, injects new pool token, deletes BootLoader key, restarts. Fixes transitioning/wrong pool/expired token. FleetCTRL passes token as first script argument.
#Category: Registration Fix
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -RunAsAdministrator
param([Parameter(Mandatory)][string]$RegistrationToken)
$ErrorActionPreference = 'Stop'

$path = 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'
Set-ItemProperty -Path $path -Name 'RegistrationToken' -Value $RegistrationToken -Force
Set-ItemProperty -Path $path -Name 'IsRegistered'      -Value 0                  -Force

Remove-Item -Path 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader' -Recurse -Force -ErrorAction SilentlyContinue

Restart-Service -Name 'RDAgentBootLoader' -Force
Start-Sleep -Seconds 10

$reg = Get-ItemProperty -Path $path
@{
    success       = ($reg.IsRegistered -eq 1 -and [string]::IsNullOrEmpty($reg.RegistrationToken))
    is_registered = $reg.IsRegistered
    token_cleared = [string]::IsNullOrEmpty($reg.RegistrationToken)
} | ConvertTo-Json