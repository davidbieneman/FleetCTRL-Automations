# Remove DisableRegistryTools Block
# Removes DisableRegistryTools GPO key that prevents agent from installing SxS stack. Fixes installMsiException errors.
#Category: Stack / SxS Fix
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$locations = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
)
$removed = 0
foreach ($loc in $locations) {
    if (Test-Path $loc) {
        $val = Get-ItemProperty -Path $loc -Name 'DisableRegistryTools' -ErrorAction SilentlyContinue
        if ($null -ne $val.DisableRegistryTools) {
            Remove-ItemProperty -Path $loc -Name 'DisableRegistryTools' -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }
}

@{ success = $true; keys_removed = $removed } | ConvertTo-Json