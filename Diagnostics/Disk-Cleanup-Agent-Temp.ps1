# Disk Cleanup (Agent Temp)
# Cleans temp files, CBS logs, and WU downloads. Fixes DownloadMsiException (Event ID 3277) caused by insufficient disk space for agent updates.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$targets = @(
    "$env:TEMP\*",
    "$env:SystemRoot\Temp\*",
    "$env:SystemRoot\Logs\CBS\*",
    "$env:SystemDrive\Windows\SoftwareDistribution\Download\*"
)
$freed = 0
foreach ($t in $targets) {
    Get-ChildItem $t -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object {
            $freed += $_.Length
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
}
@{ success = $true; freed_bytes = $freed; freed_mb = [math]::Round($freed/1MB, 1) } | ConvertTo-Json