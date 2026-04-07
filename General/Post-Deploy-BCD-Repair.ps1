# Post-Deploy BCD Repair
# Repairs BCD boot configuration after sysprep on Windows 11 24H2+.
#Category: General
#Run On: on_provision
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
# FleetCTRL Built-In: BCD Repair
$ErrorActionPreference = 'Stop'
$bcdOutput = bcdedit /enum "{current}" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Output "BCD entry missing - rebuilding"
    bcdedit /rebuildbcd /addallsources 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Output "BCD rebuilt" }
    else { Write-Output "BCD rebuild failed"; exit 1 }
} else {
    Write-Output "BCD OK"
}