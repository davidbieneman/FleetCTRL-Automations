# FSLogix: VHD Repair
# Scans and repairs corrupted VHD/VHDX file systems using Repair-Volume. Mounts read-only for scan, unmounts for offline repair if issues found. Requires Hyper-V module.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 600
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    VHD Repair — scan and repair corrupted VHD/VHDX file systems.
.DESCRIPTION
    Mounts VHD, runs Repair-Volume scan, then OfflineScanAndFix if issues found.
    Requires Hyper-V PowerShell module and admin rights.
.NOTES
    FleetCTRL Script Library | Category: Remediation & Repair
    Trigger: On-Demand | Admin Required: Yes | Destructive: Yes (modifies VHD)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TargetVHD = '',
    [switch]$ScanOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue)) {
    @{ Timestamp = [datetime]::UtcNow.ToString('o'); ComputerName = $env:COMPUTERNAME; Error = 'Hyper-V PowerShell module required for VHD repair' } | ConvertTo-Json
    return
}

$results = [System.Collections.ArrayList]::new()

function Repair-FslVhd {
    param([string]$VhdPath, [bool]$ScanOnlyMode)
    
    $entry = @{
        File   = $VhdPath
        SizeMB = [math]::Round((Get-Item $VhdPath).Length / 1MB, 1)
    }
    
    try {
        # Check if already mounted
        $vhdInfo = Get-VHD -Path $VhdPath -ErrorAction Stop
        if ($vhdInfo.Attached) {
            $entry['Status'] = 'Skipped'
            $entry['Message'] = 'VHD is currently attached — cannot repair while in use'
            return $entry
        }
        
        # Mount read-only for scan
        $mountResult = Mount-DiskImage -ImagePath $VhdPath -Access ReadOnly -PassThru -ErrorAction Stop |
            Get-DiskImage -ErrorAction Stop
        
        $diskNumber = $mountResult.Number
        
        # Get the volume
        $partition = Get-Partition -DiskNumber $diskNumber -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -ne 'Reserved' } | Select-Object -First 1
        
        if (-not $partition) {
            Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
            $entry['Status'] = 'Failed'
            $entry['Message'] = 'Could not find a valid partition on the VHD'
            return $entry
        }
        
        $volume = $partition | Get-Volume -ErrorAction SilentlyContinue
        
        if (-not $volume) {
            Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
            $entry['Status'] = 'Failed'
            $entry['Message'] = 'Could not get volume from partition'
            return $entry
        }
        
        # Scan
        $scanResult = Repair-Volume -FileSystemLabel $volume.FileSystemLabel -Scan -ErrorAction SilentlyContinue
        $entry['ScanResult'] = $scanResult
        
        # Dismount before potential repair
        Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
        
        if ($scanResult -eq 'NoErrorsFound') {
            $entry['Status'] = 'Healthy'
            $entry['Message'] = 'No file system errors found'
        } elseif ($ScanOnlyMode) {
            $entry['Status'] = 'IssuesFound'
            $entry['Message'] = "Scan found issues: $scanResult — run with -ScanOnly:$false to repair"
        } else {
            # Mount read-write for repair
            try {
                Mount-DiskImage -ImagePath $VhdPath -PassThru -ErrorAction Stop | Get-DiskImage -ErrorAction Stop | Out-Null
                $partition2 = Get-Partition -DiskNumber (Get-DiskImage -ImagePath $VhdPath).Number -ErrorAction SilentlyContinue |
                    Where-Object { $_.Type -ne 'Reserved' } | Select-Object -First 1
                $volume2 = $partition2 | Get-Volume -ErrorAction SilentlyContinue
                
                $repairResult = Repair-Volume -FileSystemLabel $volume2.FileSystemLabel -OfflineScanAndFix -ErrorAction SilentlyContinue
                $entry['RepairResult'] = $repairResult
                $entry['Status'] = 'Repaired'
                $entry['Message'] = "Repair completed: $repairResult"
            } catch {
                $entry['Status'] = 'RepairFailed'
                $entry['Message'] = $_.Exception.Message
            } finally {
                Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
            }
        }
    } catch {
        $entry['Status'] = 'Failed'
        $entry['Message'] = $_.Exception.Message
        Dismount-DiskImage -ImagePath $VhdPath -ErrorAction SilentlyContinue
    }
    
    return $entry
}

if ($TargetVHD) {
    if (Test-Path $TargetVHD) {
        [void]$results.Add((Repair-FslVhd -VhdPath $TargetVHD -ScanOnlyMode $ScanOnly))
    } else {
        [void]$results.Add(@{ File = $TargetVHD; Status = 'Failed'; Message = 'File not found' })
    }
} else {
    # Scan all containers on VHDLocations
    $profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue
    if ($profReg.VHDLocations) {
        $locations = @($profReg.VHDLocations) | ForEach-Object { $_.Trim() }
        foreach ($loc in $locations) {
            if (-not (Test-Path $loc)) { continue }
            $vhdFiles = Get-ChildItem -Path $loc -Recurse -Include '*.vhd','*.vhdx' -File -ErrorAction SilentlyContinue |
                Select-Object -First 20
            foreach ($vhd in $vhdFiles) {
                [void]$results.Add((Repair-FslVhd -VhdPath $vhd.FullName -ScanOnlyMode $ScanOnly))
            }
        }
    }
}

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    ScanOnly     = [bool]$ScanOnly
    Summary      = @{
        Total    = $results.Count
        Healthy  = ($results | Where-Object { $_.Status -eq 'Healthy' }).Count
        Repaired = ($results | Where-Object { $_.Status -eq 'Repaired' }).Count
        Issues   = ($results | Where-Object { $_.Status -eq 'IssuesFound' }).Count
        Failed   = ($results | Where-Object { $_.Status -eq 'Failed' -or $_.Status -eq 'RepairFailed' }).Count
        Skipped  = ($results | Where-Object { $_.Status -eq 'Skipped' }).Count
    }
    Results      = $results
}

$output | ConvertTo-Json -Depth 3
