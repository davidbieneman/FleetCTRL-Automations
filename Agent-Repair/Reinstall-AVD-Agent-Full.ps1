# Reinstall AVD Agent (Full)
# Complete uninstall and reinstall of AVD agent + bootloader. Requires reboot. Use when agent is corrupted or wrong version. FleetCTRL passes RegistrationToken as argument.
#Category: Agent Repair
#Run On: on_demand
#Timeout: 300
#Execution Mode: serial

#Requires -RunAsAdministrator
param(
    [Parameter(Mandatory)][string]$RegistrationToken,
    [string]$AgentInstallerUrl    = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv',
    [string]$BootloaderInstallerUrl = 'https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH'
)
$ErrorActionPreference = 'Stop'

Stop-Service -Name 'RDAgentBootLoader' -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'RdAgent' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$blPkg = Get-Package -Name 'Remote Desktop Agent Boot Loader' -ErrorAction SilentlyContinue
if ($blPkg) {
    $blCode = $blPkg.FastPackageReference
    Start-Process msiexec.exe -ArgumentList "/x $blCode /quiet /norestart" -Wait -NoNewWindow
}

$agPkg = Get-Package -Name 'Remote Desktop Services Infrastructure Agent' -ErrorAction SilentlyContinue
if ($agPkg) {
    $agCode = $agPkg.FastPackageReference
    Start-Process msiexec.exe -ArgumentList "/x $agCode /quiet /norestart" -Wait -NoNewWindow
}

Remove-Item 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent'      -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item 'HKLM:\SOFTWARE\Microsoft\RDAgentBootLoader' -Recurse -Force -ErrorAction SilentlyContinue

$agentMsi = Join-Path $env:TEMP 'Microsoft.RDInfra.RDAgent.Installer.msi'
$blMsi    = Join-Path $env:TEMP 'Microsoft.RDInfra.RDAgentBootLoader.Installer.msi'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $AgentInstallerUrl     -OutFile $agentMsi -UseBasicParsing
Invoke-WebRequest -Uri $BootloaderInstallerUrl -OutFile $blMsi    -UseBasicParsing

Start-Process msiexec.exe -ArgumentList "/i `"$agentMsi`" /quiet REGISTRATIONTOKEN=$RegistrationToken" -Wait -NoNewWindow
Start-Process msiexec.exe -ArgumentList "/i `"$blMsi`" /quiet" -Wait -NoNewWindow

Start-Sleep -Seconds 5
$reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -ErrorAction SilentlyContinue
@{
    success       = ($null -ne $reg -and $reg.IsRegistered -eq 0)
    is_registered = if ($reg) { $reg.IsRegistered } else { $null }
    note          = 'Reboot required to complete registration'
} | ConvertTo-Json