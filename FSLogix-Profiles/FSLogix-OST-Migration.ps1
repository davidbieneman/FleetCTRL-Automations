# FSLogix: OST Migration
# Migrates Outlook OST/PST data files into FSLogix Office containers. Creates VHDX, copies data, sets permissions. Adapted from Aaron Parker's migration script (MIT). Requires Hyper-V + AD modules.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 900
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    OST/PST to ODFC Migration — migrate Outlook data files into FSLogix Office containers.
.DESCRIPTION
    Creates a new ODFC VHDX container and copies OST/PST files into it.
    Sets proper permissions (user = owner + full control).
    Adapted from Aaron Parker's Migrate-OstIntoContainer.ps1 (MIT license).
.NOTES
    FleetCTRL Script Library | Category: Migration
    Trigger: On-Demand | Admin Required: Yes | Destructive: No (creates new containers)
    Prerequisites: Hyper-V module
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory = $true)]
    [string]$DestinationVHDLocation,
    
    [string]$TargetUsername = '',
    
    [int]$VHDSizeMB = 30000,
    
    [switch]$FlipFlop,
    
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Validate prerequisites
if (-not (Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue)) {
    @{ Timestamp = [datetime]::UtcNow.ToString('o'); ComputerName = $env:COMPUTERNAME; Error = 'Hyper-V PowerShell module required' } | ConvertTo-Json
    return
}

if (-not (Test-Path $SourcePath)) {
    @{ Timestamp = [datetime]::UtcNow.ToString('o'); ComputerName = $env:COMPUTERNAME; Error = "Source path not found: $SourcePath" } | ConvertTo-Json
    return
}

if (-not (Test-Path $DestinationVHDLocation)) {
    @{ Timestamp = [datetime]::UtcNow.ToString('o'); ComputerName = $env:COMPUTERNAME; Error = "Destination path not found: $DestinationVHDLocation" } | ConvertTo-Json
    return
}

$results = [System.Collections.ArrayList]::new()

# Find OST/PST files
$dataFiles = Get-ChildItem -Path $SourcePath -Recurse -Include '*.ost','*.pst' -File -ErrorAction SilentlyContinue
if ($TargetUsername) {
    $dataFiles = $dataFiles | Where-Object { $_.FullName -match $TargetUsername }
}

if ($dataFiles.Count -eq 0) {
    @{
        Timestamp    = [datetime]::UtcNow.ToString('o')
        ComputerName = $env:COMPUTERNAME
        Status       = 'NoFilesFound'
        Message      = "No OST/PST files found in $SourcePath"
    } | ConvertTo-Json
    return
}

foreach ($dataFile in $dataFiles) {
    $entry = @{
        SourceFile = $dataFile.FullName
        FileName   = $dataFile.Name
        SizeMB     = [math]::Round($dataFile.Length / 1MB, 1)
    }
    
    if ($DryRun) {
        $entry['Status'] = 'DryRun'
        $entry['Message'] = 'Would migrate this file (dry run mode)'
        [void]$results.Add($entry)
        continue
    }
    
    try {
        # Determine username from path
        $username = $null
        if ($dataFile.FullName -match '\\Users\\([^\\]+)\\') {
            $username = $Matches[1]
        } elseif ($TargetUsername) {
            $username = $TargetUsername
        }
        
        if (-not $username) {
            $entry['Status'] = 'Skipped'
            $entry['Message'] = 'Could not determine username from file path'
            [void]$results.Add($entry)
            continue
        }
        
        # Resolve SID
        $sid = $null
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($username)
            $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
        } catch {
            $entry['Status'] = 'Failed'
            $entry['Message'] = "Could not resolve SID for user: $username"
            [void]$results.Add($entry)
            continue
        }
        
        # Determine folder name
        $folderName = if ($FlipFlop) { "${username}_${sid}" } else { "${sid}_${username}" }
        $containerDir = Join-Path -Path $DestinationVHDLocation -ChildPath $folderName
        $vhdxPath = Join-Path -Path $containerDir -ChildPath "ODFC_${username}.VHDX"
        
        # Create directory
        if (-not (Test-Path $containerDir)) {
            New-Item -Path $containerDir -ItemType Directory -Force | Out-Null
        }
        
        # Create VHDX if it doesn't exist
        if (-not (Test-Path $vhdxPath)) {
            $vhdSizeBytes = [int64]$VHDSizeMB * 1MB
            New-VHD -Path $vhdxPath -SizeBytes $vhdSizeBytes -Dynamic -ErrorAction Stop | Out-Null
            
            # Mount and format
            $mountResult = Mount-DiskImage -ImagePath $vhdxPath -PassThru -ErrorAction Stop |
                Get-DiskImage -ErrorAction Stop
            $diskNumber = $mountResult.Number
            
            Initialize-Disk -Number $diskNumber -PartitionStyle GPT -ErrorAction Stop
            $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -ErrorAction Stop
            Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "ODFC_$username" -Confirm:$false -ErrorAction Stop | Out-Null
            
            # Add access path
            $driveLetter = $partition | Add-PartitionAccessPath -AssignDriveLetter -PassThru |
                Get-Partition | Select-Object -ExpandProperty DriveLetter
            
            if (-not $driveLetter) {
                $entry['Status'] = 'Failed'
                $entry['Message'] = 'Could not assign drive letter to new VHDX'
                Dismount-DiskImage -ImagePath $vhdxPath -ErrorAction SilentlyContinue
                [void]$results.Add($entry)
                continue
            }
            
            $mountPath = "${driveLetter}:\"
        } else {
            # Mount existing
            $mountResult = Mount-DiskImage -ImagePath $vhdxPath -PassThru -ErrorAction Stop |
                Get-DiskImage -ErrorAction Stop
            $partition = Get-Partition -DiskNumber $mountResult.Number -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -ne 'Reserved' } | Select-Object -First 1
            $driveLetter = $partition.DriveLetter
            $mountPath = "${driveLetter}:\"
        }
        
        # Create ODFC folder structure
        $odfcDir = Join-Path -Path $mountPath -ChildPath 'ODFC'
        if (-not (Test-Path $odfcDir)) {
            New-Item -Path $odfcDir -ItemType Directory -Force | Out-Null
        }
        
        # Copy the data file
        $destFile = Join-Path -Path $odfcDir -ChildPath $dataFile.Name
        Copy-Item -Path $dataFile.FullName -Destination $destFile -Force -ErrorAction Stop
        
        # Set permissions
        try {
            $acl = Get-Acl -Path $containerDir
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $ntAccount, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($rule)
            $acl.SetOwner($ntAccount)
            Set-Acl -Path $containerDir -AclObject $acl -ErrorAction SilentlyContinue
        } catch { }
        
        # Dismount
        Dismount-DiskImage -ImagePath $vhdxPath -ErrorAction SilentlyContinue
        
        $entry['Status'] = 'Migrated'
        $entry['Username'] = $username
        $entry['SID'] = $sid
        $entry['ContainerPath'] = $vhdxPath
        $entry['Message'] = "Successfully migrated $($dataFile.Name) into ODFC container"
        
    } catch {
        $entry['Status'] = 'Failed'
        $entry['Message'] = $_.Exception.Message
        # Clean up mount
        if ($vhdxPath) { Dismount-DiskImage -ImagePath $vhdxPath -ErrorAction SilentlyContinue }
    }
    
    [void]$results.Add($entry)
}

$output = @{
    Timestamp    = [datetime]::UtcNow.ToString('o')
    ComputerName = $env:COMPUTERNAME
    DryRun       = [bool]$DryRun
    Summary      = @{
        TotalFiles = $results.Count
        Migrated   = ($results | Where-Object { $_.Status -eq 'Migrated' }).Count
        Failed     = ($results | Where-Object { $_.Status -eq 'Failed' }).Count
        Skipped    = ($results | Where-Object { $_.Status -eq 'Skipped' }).Count
        DryRun     = ($results | Where-Object { $_.Status -eq 'DryRun' }).Count
    }
    Results      = $results
}

$output | ConvertTo-Json -Depth 3
