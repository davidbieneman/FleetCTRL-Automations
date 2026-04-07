# FSLogix: Version & Platform Detection
# Identifies exact FSLogix version (RTM vs CU1), VDI platform (AVD, W365, Citrix, VMware, RDS), OS type, and PowerShell/Hyper-V module availability.
#Category: Diagnostics
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    FSLogix Version & Platform Detection.
.DESCRIPTION
    Identifies exact FSLogix version (RTM vs CU1), VDI platform, OS type,
    and module availability. Locale-safe: uses registry, WMI ProductType, BuildNumber.
.NOTES
    FleetCTRL Script Library | Category: Configuration & Discovery
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

# --- FSLogix Version ---
$installPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Apps' -Name 'InstallPath' -ErrorAction SilentlyContinue).InstallPath
$fslogixVersion = $null
$isCU1 = $null
$isRTM = $null

if ($installPath) {
    $frxsvc = Join-Path -Path $installPath -ChildPath 'frxsvc.exe'
    if (Test-Path -Path $frxsvc) {
        $vi = (Get-Item -Path $frxsvc).VersionInfo
        $fslogixVersion = @{
            FileVersion    = $vi.FileVersion
            ProductVersion = $vi.ProductVersion
            Major          = $vi.FileMajorPart
            Minor          = $vi.FileMinorPart
            Build          = $vi.FileBuildPart
            Revision       = $vi.FilePrivatePart
        }
        # 26.01 RTM vs CU1 detection: CU1 has higher build/revision
        # RTM = 2.9.89xx.xxxxx range, CU1 has specific higher revision
        $verString = $vi.FileVersion
        if ($verString -match '^2\.9\.89') {
            $isRTM = $true
            $isCU1 = $false
        } elseif ($verString -match '^2\.9\.9') {
            $isRTM = $false
            $isCU1 = $true
        }
    }
}

# --- VDI Platform Detection (registry-based, locale-safe) ---
$platform = 'Physical/Unknown'
$platformDetails = @{}

# AVD
$rdAgent = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\RDInfraAgent' -ErrorAction SilentlyContinue
if ($rdAgent) {
    $platform = 'Azure Virtual Desktop'
    $platformDetails['RDAgentVersion'] = $rdAgent.AgentVersion
    $platformDetails['IsRegistered'] = $rdAgent.IsRegistered
}

# Windows 365
if ($env:CLOUD_PC -eq '1' -or (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows 365' -ErrorAction SilentlyContinue)) {
    $platform = 'Windows 365'
}

# Citrix
$citrix = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Citrix\VirtualDesktopAgent' -ErrorAction SilentlyContinue
if ($citrix) {
    $platform = 'Citrix Virtual Apps and Desktops'
    $platformDetails['CitrixVersion'] = $citrix.ProductVersion
}

# VMware Horizon / Omnissa
$vmware = Get-ItemProperty -Path 'HKLM:\SOFTWARE\VMware, Inc.\VMware VDM' -ErrorAction SilentlyContinue
if ($vmware) {
    $platform = 'VMware Horizon / Omnissa'
}

# RDS (fallback)
if ($platform -eq 'Physical/Unknown') {
    $sessionName = $env:SESSIONNAME
    if ($sessionName -and $sessionName -match '^RDP-') {
        $platform = 'Remote Desktop Services'
    }
}

# Hyper-V Guest detection (WMI, locale-safe)
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
if ($computerSystem.Model -eq 'Virtual Machine') {
    $platformDetails['IsVirtualMachine'] = $true
    $platformDetails['Manufacturer'] = $computerSystem.Manufacturer
} else {
    $platformDetails['IsVirtualMachine'] = $false
}

# --- OS Detection (locale-safe: use ProductType + BuildNumber, not Caption) ---
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$osInfo = @{}
if ($os) {
    $productType = $os.ProductType  # 1=Workstation, 2=DomainController, 3=Server
    $build = [int]$os.BuildNumber
    
    $osInfo['BuildNumber'] = $build
    $osInfo['ProductType'] = $productType
    $osInfo['Caption'] = $os.Caption  # may be localized, included for display only
    $osInfo['Version'] = $os.Version
    $osInfo['Architecture'] = $os.OSArchitecture
    
    # Multi-session detection
    $isMultiSession = $false
    if ($productType -eq 1) {
        # Check for Enterprise Multi-Session via registry (not caption parsing)
        $sku = (Get-CimInstance -ClassName Win32_OperatingSystem).OperatingSystemSKU
        # SKU 175 = Enterprise Multi-Session
        if ($sku -eq 175) {
            $isMultiSession = $true
        }
    }
    $osInfo['IsMultiSession'] = $isMultiSession
    $osInfo['IsServer'] = ($productType -ne 1)
    
    # Friendly name (derived from build + type, not localized caption)
    $friendlyName = switch ($build) {
        { $_ -ge 26100 } { 'Windows 11 24H2 / Server 2025' }
        { $_ -ge 22631 } { 'Windows 11 23H2' }
        { $_ -ge 22621 } { 'Windows 11 22H2' }
        { $_ -ge 22000 } { 'Windows 11 21H2' }
        { $_ -ge 19045 } { 'Windows 10 22H2' }
        { $_ -ge 19044 } { 'Windows 10 21H2' }
        { $_ -ge 20348 } { 'Server 2022' }
        { $_ -ge 17763 } { 'Windows 10 1809 / Server 2019' }
        { $_ -ge 14393 } { 'Windows 10 1607 / Server 2016' }
        default { "Build $build" }
    }
    $osInfo['FriendlyName'] = $friendlyName
}

# --- Module / Dependency Availability ---
$dependencies = @{
    PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
    PowerShellEdition   = $PSVersionTable.PSEdition
    HyperVModule        = [bool](Get-Module -ListAvailable -Name 'Hyper-V' -ErrorAction SilentlyContinue)
    FSLogixModule       = [bool](Get-Module -ListAvailable -Name 'Microsoft.FSLogix' -ErrorAction SilentlyContinue)
    ActiveDirectoryModule = [bool](Get-Module -ListAvailable -Name 'ActiveDirectory' -ErrorAction SilentlyContinue)
}

# --- Output ---
$output = @{
    Timestamp      = [datetime]::UtcNow.ToString('o')
    ComputerName   = $env:COMPUTERNAME
    FSLogixVersion = $fslogixVersion
    IsRTM          = $isRTM
    IsCU1          = $isCU1
    FSLogixInstallPath = $installPath
    VDIPlatform    = $platform
    PlatformDetails = $platformDetails
    OperatingSystem = $osInfo
    Dependencies   = $dependencies
}

$output | ConvertTo-Json -Depth 4
