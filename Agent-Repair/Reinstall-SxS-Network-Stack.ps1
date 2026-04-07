# Reinstall SxS Network Stack
# Uninstalls and reinstalls the RDP side-by-side stack MSI. Fixes InstallationHealthCheckFailedException and missing rdp-sxs listener in qwinsta.
#Category: Agent Repair
#Run On: on_demand
#Timeout: 120
#Execution Mode: serial

#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

$sxsPkg = Get-Package -Name 'Remote Desktop Services SxS Network Stack' -ErrorAction SilentlyContinue
if (-not $sxsPkg) {
    @{ success = $false; error = 'sxs_package_not_found' } | ConvertTo-Json
    exit 1
}

$productCode = $sxsPkg.FastPackageReference
try {
    Start-Process msiexec.exe -ArgumentList "/x $productCode /quiet /norestart" -Wait -NoNewWindow
} catch {
    @{ success = $false; error = "uninstall_failed: $($_.Exception.Message)" } | ConvertTo-Json
    exit 1
}

$rdInfraDir = Join-Path $env:ProgramFiles 'Microsoft RDInfra'
$sxsMsi = Get-ChildItem -Path $rdInfraDir -Filter 'SxSStack*.msi' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $sxsMsi) {
    @{ success = $false; error = 'sxs_msi_not_found_in_rdinfra' } | ConvertTo-Json
    exit 1
}

Start-Process msiexec.exe -ArgumentList "/i `"$($sxsMsi.FullName)`" /quiet /norestart" -Wait -NoNewWindow

Restart-Service -Name 'RDAgentBootLoader' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$qwinsta = & qwinsta 2>$null
$sxsLine = $qwinsta | Where-Object { $_ -match 'rdp-sxs' }

@{
    success    = ($null -ne $sxsLine)
    sxs_state  = if ($sxsLine) { 'present' } else { 'missing' }
    msi_used   = $sxsMsi.Name
} | ConvertTo-Json