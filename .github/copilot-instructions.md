# OSDCloud Zero-Touch Deployment System

## Project Overview
This is an OSDCloud-based Windows 11 zero-touch installation (ZTI) automation framework for enterprise device provisioning with Windows Autopilot integration. Scripts orchestrate the complete deployment lifecycle: pre-OS selection, OS installation, post-OS configuration, and Autopilot registration.

## Architecture & Deployment Flow

### 1. Entry Points
- **`OSDCloud_Start.ps1`**: Main launcher - installs OSD module and launches `Start-OSDPad` with GitHub repo integration (`-RepoOwner Lenander88 -RepoName OSDCloud -RepoFolder ScriptPad`)
- **`StartURL-Live-01_EDU.ps1`**: EDU variant with CSV-driven build selection (downloads `EDU.csv`, presents Windows Forms ComboBox)
- **`StartURL-Live-01_SelectOSBuild.ps1`**: OS Build selector (23H2/24H2/25H2 from `OSBuild.csv`)
- **`StartURL-Live-01.ps1`**: Standard ZTI with hardcoded 24H2 deployment

### 2. Pre-OS Phase (WinPE)
Scripts run in WinPE before OS installation:
- **Serial number validation**: All scripts retrieve `(Get-WmiObject -Class Win32_BIOS).SerialNumber` and validate presence
- **Autopilot verification**: POST device serial to Azure Logic App URI to check Autopilot pre-registration status
- **Hardware hash generation**: If `$result.Response -eq 0` (not registered), use `oa3tool.exe` to extract hardware hash, prompt for group tag selection via `grouptags.csv`, and export to USB as `$serialNumber.csv`
- **CSV-driven configuration**: 
  - `EDU.csv`: Maps friendly names to `Invoke-WebRequest` commands for SetupComplete variants
  - `grouptags.csv`: Provides Autopilot group tag options (MEM-Global-Standard, Softwarecraft, etc.)
  - `OSBuild.csv`: Lists available Windows 11 builds

### 3. OS Installation
All variants call `Start-OSDCloud` with splatted parameters:
```powershell
$Params = @{
    OSVersion = "Windows 11"
    OSBuild = "24H2"  # or from CSV selection
    OSEdition = "Pro" # or "Enterprise"
    OSLanguage = "en-us"
    OSLicense = "Retail" # or "Volume"
    ZTI = $true
    Firmware = $true
}
Start-OSDCloud @Params
```

### 4. Post-OS SetupComplete Chain
**Critical execution order** (`C:\Windows\Setup\Scripts\SetupComplete.ps1` runs automatically after Windows setup):

1. **`SetupComplete.ps1`** (root script, location: `C:\Windows\Setup\Scripts\SetupComplete.ps1`)
   - Imports OSD module
   - Sets High Performance power plan during setup
   - Executes custom `SetupComplete.cmd` from `C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd`
   - Disables Windows automatic BitLocker encryption via registry: `HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker` → `PreventDeviceEncryption = 1`
   - Restores Balanced power plan
   - Reboots

2. **`SetupComplete.cmd`** (called by SetupComplete.ps1)
   - Launches `Install-LCU.ps1` with `powershell.exe -ExecutionPolicy Bypass`

3. **`Install-LCU.ps1`** (updates installation)
   - Imports pre-staged `PSWindowsUpdate` module (staged by `Save-Module` during pre-OS)
   - Runs `Get-WindowsUpdate -MicrosoftUpdate -Category "Security Updates","Critical Updates","Updates" -AcceptAll -Install -IgnoreReboot`
   - Retries up to 3 times with 60-second delays

### 5. OOBE Phase
After first boot, `OOBE.ps1` or `oobetasks.ps1` orchestrate Autopilot registration:
- **`oobetasks.ps1`**: Creates scheduled tasks via `Schedule.Service` COM object to run OOBE scripts with ServiceUI.exe (triggers at logon with 15/20 second delays)
- **`OOBE.ps1`**: Configures keyboard language (de-CH), removes Appx packages, adds capabilities, updates drivers/Windows, registers device with Autopilot

## Key Patterns & Conventions

### Windows Forms UI Pattern
All interactive prompts use consistent Windows Forms structure:
```powershell
Add-Type -AssemblyName System.Windows.Forms
$form = New-Object System.Windows.Forms.Form
$form.Text = "Selection Title"
$form.Size = New-Object System.Drawing.Size(300,150)
$form.StartPosition = "CenterScreen"

$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.DropDownStyle = 'DropDownList'  # Prevent typing
# Populate from CSV: Import-CSV $csvPath | ForEach-Object { $comboBox.Items.Add($_.ColumnName) }

$okButton = New-Object System.Windows.Forms.Button
$okButton.Add_Click({ $script:variableName = $comboBox.SelectedItem; $form.Close() })
$form.ShowDialog()
```

### CSV-Driven Configuration
Configuration externalized to GitHub-hosted CSVs (enables updates without script changes):
- Download with cache check: `if (!(Test-Path $csvPath) -or ((Get-Item $csvPath).LastWriteTime -lt (Get-Date).AddDays(-1)))`
- Schema: `OptionName,Value` where Value is executable PowerShell command or data

### Script Staging Pattern
Pre-OS scripts download and stage post-OS scripts:
```powershell
# Stage module for offline use
Save-Module -Name PSWindowsUpdate -Path 'C:\Program Files\WindowsPowerShell\Modules' -Force

# Stage SetupComplete scripts
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/[org]/[repo]/[branch]/SetupComplete.ps1' `
    -OutFile C:\Windows\Setup\Scripts\SetupComplete.ps1
```

### Environment Setup for System Context
Scripts running in SYSTEM context (OOBE, Autopilot) standardize environment:
```powershell
$env:APPDATA = "C:\Windows\System32\Config\SystemProfile\AppData\Roaming"
$env:LOCALAPPDATA = "C:\Windows\System32\Config\SystemProfile\AppData\Local"
$Env:PSModulePath = $env:PSModulePath+";C:\Program Files\WindowsPowerShell\Scripts"
$env:Path = $env:Path+";C:\Program Files\WindowsPowerShell\Scripts"
```

### Logging Convention
All OOBE/Autopilot scripts use transcript logging:
```powershell
$Global:Transcript = "$((Get-Date).ToString('yyyy-MM-dd-HHmmss'))-ScriptName.log"
Start-Transcript -Path (Join-Path "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\" $Global:Transcript) -ErrorAction Ignore
# ... script logic ...
Stop-Transcript
```

## Variant Differences

### Education (EDU) Build
- **CSV-driven SetupComplete selection**: `EDU.csv` maps to different SetupComplete scripts (Standard, Stockholm, Ballerup)
- **Special variants**: `Setup_Stockholm.ps1` includes local admin account creation and computer renaming to `SESTV-$serialNumber`

### OS Build Selection
- Dynamic selection from `OSBuild.csv` (23H2, 24H2, 25H2)
- Build number interpolated into `Start-OSDCloud -OSBuild $OSBuild`

## Common Development Tasks

### Adding New EDU Variant
1. Create new `Setup_[Location].ps1` with custom post-setup logic
2. Add row to `EDU.csv`: `LocationName,Invoke-WebRequest -Uri 'https://...Setup_Location.ps1' -OutFile C:\Windows\Setup\Scripts\SetupComplete.ps1`
3. Test CSV download and selection UI

### Modifying Autopilot Group Tags
1. Edit `grouptags.csv` (hosted on GitHub)
2. Schema: `OptionName,Value` (OptionName displayed in UI, Value used for Autopilot GroupTag)
3. Changes apply immediately (CSV downloaded fresh each run)

### Debugging SetupComplete Chain
- Check transcript logs in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\`
- Verify script staging: `Test-Path C:\Windows\Setup\Scripts\SetupComplete.ps1`
- Confirm PSWindowsUpdate staged: `Get-Module -ListAvailable PSWindowsUpdate`

## Integration Points

### External Dependencies
- **OSD PowerShell Module**: Core OSDCloud functionality (`Start-OSDCloud`, `Start-OSDPad`)
- **PSWindowsUpdate Module**: Windows Update automation (pre-staged with `Save-Module`)
- **Azure Logic App**: Autopilot pre-registration verification (hardcoded URI in scripts)
- **GitHub Raw URLs**: Script and CSV hosting (`raw.githubusercontent.com/Lenander88/OSDCloud/dev/`)

### Autopilot Registration Flow
1. **Pre-check**: POST serial number to Logic App (result code 0 = not registered)
2. **Hash generation**: `oa3tool.exe` with `OA3.cfg` produces `OA3.xml`
3. **Manual upload**: Hash saved to USB, technician uploads to Intune
4. **OOBE registration**: `Autopilot.ps1` or `Start-AutopilotOOBE.ps1` completes registration using Graph API with certificate authentication

## File Organization
- **Root**: Entry point scripts and shared utilities
- **`ScriptPad/`**: Scripts loaded by `Start-OSDPad` (e.g., `W11_OOBEcmd.ps1`)
- **CSV files**: Configuration data (EDU.csv, grouptags.csv, OSBuild.csv)
- **Runtime paths**:
  - `C:\OSDCloud\Scripts\SetupComplete\`: Custom post-setup scripts
  - `C:\Windows\Setup\Scripts\`: Windows automatic execution path
  - `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\OSD\`: Consolidated logs

## Testing Guidance
- Test in VM (scripts detect virtual machines with `Get-MyComputerModel -match 'Virtual'` and adjust display resolution)
- USB detection for hash export: `Get-WmiObject -Namespace "root\cimv2" -Query "SELECT * FROM Win32_LogicalDisk WHERE DriveType = 2"`
- Serial number edge cases: Scripts validate serial exists before proceeding (shutdown if missing)

## Current Branch
Repository: `Lenander88/OSDCloud`, Branch: `dev` (check raw URLs and update if deploying from different branch)
