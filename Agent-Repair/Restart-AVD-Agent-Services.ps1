# Restart AVD Agent Services
# Force-restarts RdAgent and RDAgentBootLoader. Fixes 90% of random "went unhealthy" situations. Microsoft recommended first step.
#Category: Agent Repair
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

Stop-Service -Name 'RDAgentBootLoader' -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'RdAgent' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Start-Service -Name 'RdAgent' -ErrorAction Stop
Start-Sleep -Seconds 3
Start-Service -Name 'RDAgentBootLoader' -ErrorAction Stop

$rdAgent    = Get-Service -Name 'RdAgent'
$bootLoader = Get-Service -Name 'RDAgentBootLoader'

@{
    success           = ($rdAgent.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running -and
                         $bootLoader.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running)
    rdagent_status    = $rdAgent.Status.ToString()
    bootloader_status = $bootLoader.Status.ToString()
} | ConvertTo-Json