# FleetCTRL Automations

PowerShell automation scripts for Azure Virtual Desktop session host management. Used with [FleetCTRL](https://liquidware.com) via the GitHub Repository integration in Settings.

## Setup

1. In FleetCTRL, go to **Settings > GitHub Repositories**
2. Click **Add Repository**
3. Enter: `liquidwarelabs/FleetCTRL-Automations`, branch `main`
4. Click **Browse & Select** to import the scripts you need

## Categories

Scripts are organized by function:

| Category | Description |
|----------|-------------|
| Diagnostic | AVD agent diagnostics and health checks |
| Environment | System checks (disk, .NET, connectivity, pending reboots) |
| FSLogix | Profile container management, health, cloud cache, remediation |
| Install / Reinstall | AVD agent installation and reinstallation |
| Log Collection | Diagnostic log gathering |
| Maintenance | Windows Updates, M365 Updates, Defender signatures |
| Registration Fix | AVD agent re-registration and pool migration |
| Session Management | Session logoff and management |
| Soft Fix | Service restarts and non-destructive fixes |
| Stack / SxS Fix | RD SxS network stack reinstallation |

## Script Format

Each script includes metadata headers:

```powershell
# Script Name
# Description
#Category: Category Name
#Run On: on_demand
#Timeout: 600
#Execution Mode: serial
```

FleetCTRL auto-detects `#Category` from the script header during import.

## License

Copyright Liquidware. All rights reserved.
