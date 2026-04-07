# Install AVD Agent (Fresh)
# Installs AVD agent from scratch on a VM with no agent. Requires reboot. Use diagnose_agent first to confirm agent is truly missing.
#Category: Install / Reinstall
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

$existing = Get-Package -Name 'Remote Desktop Services Infrastructure Agent' -ErrorAction SilentlyContinue
if ($existing) {
    @{ success = $false; error = 'agent_already_installed'; version = $existing.Version } | ConvertTo-Json
    exit 1
}

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
    success       = ($null -ne $reg)
    is_registered = if ($reg) { $reg.IsRegistered } else { $null }
    note          = 'Reboot required to complete registration'
} | ConvertTo-Json