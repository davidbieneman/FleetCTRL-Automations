# FSLogix: Restart Services
# Restarts FSLogix profile container services. Fixes VHD mount failures after service crash or timeout.
#Category: FSLogix
#Run On: on_demand
#Timeout: 30
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'SilentlyContinue'

$services = @('frxsvc', 'frxccds')
$results = @{}

foreach ($sn in $services) {
    $svc = Get-Service -Name $sn -ErrorAction SilentlyContinue
    if (-not $svc) {
        $results[$sn] = 'not_installed'
        continue
    }
    try {
        Restart-Service -Name $sn -Force -ErrorAction Stop
        Start-Sleep -Seconds 2
        $svc = Get-Service -Name $sn
        $results[$sn] = $svc.Status.ToString()
    } catch {
        $results[$sn] = "restart_failed: $($_.Exception.Message)"
    }
}

$allOk = ($results.Values | Where-Object { $_ -ne 'Running' -and $_ -ne 'not_installed' }).Count -eq 0
@{ success = $allOk; services = $results } | ConvertTo-Json -Depth 2