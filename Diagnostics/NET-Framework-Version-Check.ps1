# .NET Framework Version Check
# Checks if .NET 4.7.2+ is installed. MissingMethodException (Event ID 3389) means .NET is too old for agent updates. Diagnostic only.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$installed = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
$isOk = ($installed -ge 461808)
@{
    success         = $isOk
    release_number  = $installed
    meets_minimum   = $isOk
    action_required = $(if (-not $isOk) { 'upgrade_dotnet_to_472' } else { 'none' })
} | ConvertTo-Json