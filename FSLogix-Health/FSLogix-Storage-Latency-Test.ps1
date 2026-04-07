# FSLogix: Storage Latency Test
# Measures read/write latency to all configured VHDLocations paths. Rates as Excellent/Good/Fair/Poor with threshold-based classification.
#Category: FSLogix: Health
#Run On: on_demand
#Timeout: 60
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    FSLogix Storage Latency Test — measure read/write to VHDLocations.
.NOTES
    FleetCTRL Script Library | Category: Health & Diagnostics
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param(
    [int]$TestSizeKB = 1024
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-StorageLatency {
    param([string]$Path, [int]$SizeKB)
    
    $result = @{ Path = $Path; Accessible = $false }
    
    if (-not (Test-Path -Path $Path)) {
        $result['Error'] = 'Path not accessible'
        return $result
    }
    
    $result['Accessible'] = $true
    $tempFile = Join-Path -Path $Path -ChildPath "fleetctrl_latency_test_$([guid]::NewGuid().ToString('N').Substring(0,8)).tmp"
    $testData = [byte[]]::new($SizeKB * 1024)
    [System.Random]::new().NextBytes($testData)
    
    try {
        # Write test
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        [System.IO.File]::WriteAllBytes($tempFile, $testData)
        $sw.Stop()
        $writeMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        
        # Read test
        $sw.Restart()
        [void][System.IO.File]::ReadAllBytes($tempFile)
        $sw.Stop()
        $readMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        
        # Rating
        $readRating = switch ($readMs) {
            { $_ -lt 5 }   { 'Excellent' }
            { $_ -lt 20 }  { 'Good' }
            { $_ -lt 50 }  { 'Fair' }
            default         { 'Poor' }
        }
        $writeRating = switch ($writeMs) {
            { $_ -lt 10 }  { 'Excellent' }
            { $_ -lt 40 }  { 'Good' }
            { $_ -lt 100 } { 'Fair' }
            default         { 'Poor' }
        }
        
        $result['WriteLatencyMs'] = $writeMs
        $result['ReadLatencyMs'] = $readMs
        $result['WriteRating'] = $writeRating
        $result['ReadRating'] = $readRating
        $result['TestSizeKB'] = $SizeKB
    } catch {
        $result['Error'] = $_.Exception.Message
    } finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
    
    return $result
}

# Get all configured paths
$results = [System.Collections.ArrayList]::new()
$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
$odfcReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\ODFC' -ErrorAction SilentlyContinue

$paths = @()
if ($profReg.VHDLocations) { $paths += @($profReg.VHDLocations) }
if ($odfcReg.VHDLocations) { $paths += @($odfcReg.VHDLocations) }
$paths = $paths | Where-Object { $_ -and $_.Trim() } | Select-Object -Unique

if ($paths.Count -eq 0) {
    $output = @{
        Timestamp = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        Error = 'No VHDLocations configured'
        Results = @()
    }
} else {
    foreach ($p in $paths) {
        [void]$results.Add((Test-StorageLatency -Path $p.Trim() -SizeKB $TestSizeKB))
    }
    $output = @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        Results      = $results
    }
}

$output | ConvertTo-Json -Depth 3
