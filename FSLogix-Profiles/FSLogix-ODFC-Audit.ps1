# FSLogix: ODFC Audit
# Full dump of Office Data File Container settings including all Include flags (Outlook, OneDrive, Teams, OneNote, SharePoint), deprecated IncludeSkype detection, and single vs dual container mode.
#Category: FSLogix: Profiles
#Run On: on_demand
#Timeout: 15
#Execution Mode: serial

#Requires -Version 5.1
<#
.SYNOPSIS
    ODFC Configuration Audit — Office Data File Container settings.
.NOTES
    FleetCTRL Script Library | Category: Office 365 Container
    Trigger: On-Demand | Admin Required: No | Destructive: No
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$odfcReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\ODFC' -ErrorAction SilentlyContinue
$profReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue

# Determine container mode
$profileEnabled = $profReg -and $profReg.Enabled -eq 1
$odfcEnabled = $odfcReg -and $odfcReg.Enabled -eq 1

$containerMode = if ($profileEnabled -and $odfcEnabled) { 'Dual (Profile + ODFC separate)' }
    elseif ($profileEnabled -and -not $odfcEnabled) { 'Single (Profile Container includes O365 data)' }
    elseif (-not $profileEnabled -and $odfcEnabled) { 'ODFC Only' }
    else { 'None configured' }

$flags = @()

$includeFlags = @{
    IncludeOutlook             = @{ Value = $odfcReg.IncludeOutlook; Desc = 'Outlook OST/cache' }
    IncludeOneDrive            = @{ Value = $odfcReg.IncludeOneDrive; Desc = 'OneDrive sync data' }
    IncludeTeams               = @{ Value = $odfcReg.IncludeTeams; Desc = 'Teams data' }
    IncludeOneNote             = @{ Value = $odfcReg.IncludeOneNote; Desc = 'OneNote notebooks' }
    IncludeOneNote_UWP         = @{ Value = $odfcReg.IncludeOneNote_UWP; Desc = 'OneNote UWP app' }
    IncludeSharePoint          = @{ Value = $odfcReg.IncludeSharePoint; Desc = 'SharePoint cache' }
    IncludeOfficeActivation    = @{ Value = $odfcReg.IncludeOfficeActivation; Desc = 'Office activation data' }
    IncludeSkype               = @{ Value = $odfcReg.IncludeSkype; Desc = 'Skype for Business (DEPRECATED - EOL Oct 2025)' }
    IncludeOutlookPersonalization = @{ Value = $odfcReg.IncludeOutlookPersonalization; Desc = 'Outlook view/personalization settings' }
}

if ($odfcReg.IncludeSkype -eq 1) {
    $flags += @{ Level = 'Warning'; Message = 'IncludeSkype is enabled — Skype for Business reached EOL Oct 2025. Disable to reduce container bloat.' }
}
if ($containerMode -eq 'Dual (Profile + ODFC separate)') {
    $flags += @{ Level = 'Info'; Message = 'Running dual-container mode. Microsoft recommends single-container (Profile only) for simplicity.' }
}
if ($odfcEnabled -and -not $odfcReg.VHDLocations -and -not $odfcReg.CCDLocations) {
    $flags += @{ Level = 'Error'; Message = 'ODFC is enabled but no VHDLocations or CCDLocations configured for ODFC.' }
}

$output = @{
    Timestamp     = [datetime]::UtcNow.ToString('o')
    ComputerName  = $env:COMPUTERNAME
    ContainerMode = $containerMode
    OdfcEnabled   = $odfcEnabled
    OdfcConfig    = @{
        VHDLocations         = $odfcReg.VHDLocations
        CCDLocations         = $odfcReg.CCDLocations
        SizeInMBs            = $odfcReg.SizeInMBs
        VolumeType           = $odfcReg.VolumeType
        MirrorLocalOSTToVHD  = $odfcReg.MirrorLocalOSTToVHD
        RefreshUserPolicy    = $odfcReg.RefreshUserPolicy
    }
    IncludeFlags  = $includeFlags
    Flags         = $flags
}

$output | ConvertTo-Json -Depth 4
