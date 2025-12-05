# OSDCloud SetupComplete.ps1; Location: C:\Windows\Setup\Scripts\Setup_Stockholm.ps1
# Logs setup process, imports OSD modules, sets power plan, runs custom SetupComplete.cmd, and reboots when finished.

##================================================
## MARK: Configuration Variables
##================================================
# Local User Configuration
$LocalUserName = 'EDU'
$LocalUserPassword = 'Assa#26144'
$LocalUserFullName = 'Education User'
$LocalUserDescription = 'Local administrator account for EDU purposes'

# Computer Configuration
$ComputerNamePrefix = 'SESTVL'

# Regional and Localization Settings
$RegionalLocale = 'sv-SE' # Sweden = 'sv-SE' # Denmark = 'da-DK' # Finland = 'fi-FI' # Norway = 'nb-NO'
$RegionalCountry = 'Sweden' # Sweden = 'Sweden' # Denmark = 'Denmark' # Finland = 'Finland' # Norway = 'Norway'
$RegionalLanguage = 'SVE' # Swedish = 'SVE' # Danish = 'DAN' # Finnish = 'FIN' # Norwegian = 'NOR'
$TimeZoneId = 'W. Europe Standard Time' # Stockholm = 'W. Europe Standard Time' # Copenhagen = 'Romance Standard Time' # Helsinki = 'FLE Standard Time' # Oslo = 'W. Europe Standard Time'
$KeyboardLayoutId = '0000041d'  # Swedish = '0000041d' # Danish = '00000406' # Finnish = '0000040b' # Norwegian = '00000414'
$InstallLanguageId = '041d'     # Swedish = '041d' # Danish = '0406' # Finnish = '040b' # Norwegian = '0414'

# Logging first
$StartTime = Get-Date
Start-Transcript -Path 'C:\OSDCloud\Logs\SetupComplete.log' -ErrorAction Ignore
Write-Host "Starting SetupComplete Script Process"
Write-Host ("Start Time: {0}" -f $StartTime.ToString("HH:mm:ss"))

# Module import (OSD)
try {
    Import-Module OSD -Force -ErrorAction Stop
} catch {
    $ModulePath = (Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\Modules\osd" -Directory | Select-Object -Last 1).FullName
    if ($ModulePath) { Import-Module "$ModulePath\OSD.psd1" -Force }
}

# Optional: pull OSD Anywhere helpers
try {
    Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/OSDeploy/OSD/master/cloud/modules/_anywhere.psm1')
} catch {
    Write-Warning "Could not load _anywhere.psm1: $($_.Exception.Message)"
}
Start-Sleep -Seconds 10


# Power plan: High performance during post-setup
Write-Host 'Setting PowerPlan to High Performance'
powercfg /setactive DED574B5-45A0-4F42-8737-46345C09C238 | Out-Null
Write-Host 'Confirming PowerPlan [powercfg /getactivescheme]'
powercfg /getactivescheme

# Keep the device awake while we run post-setup tasks
powercfg -x -standby-timeout-ac 0
powercfg -x -standby-timeout-dc 0
powercfg -x -hibernate-timeout-ac 0
powercfg -x -hibernate-timeout-dc 0
Set-PowerSettingSleepAfter -PowerSource AC -Minutes 0
Set-PowerSettingTurnMonitorOffAfter -PowerSource AC -Minutes 0

# Run your custom SetupComplete.cmd if present
Write-Output 'Running Scripts in Custom OSDCloud SetupComplete Folder'
$SetupCompletePath = "C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd"
if (Test-Path $SetupCompletePath) {
    $SetupComplete = Get-ChildItem $SetupCompletePath -Filter SetupComplete.cmd
    if ($SetupComplete) {cmd.exe /c start /wait "" "$($SetupComplete.FullName)"}
} else {
    Write-Host "No custom SetupComplete.cmd found at $SetupCompletePath"
}

# Renaming to [ComputerNamePrefix]-[serialnumber]
# Test if serial number can be retrieved rename computer accordingly otherwise log error message.

if ((Get-CimInstance Win32_BIOS).SerialNumber) {
    Write-Host "Retrieving Device Serial Number"
    $serialNumber = (Get-CimInstance Win32_BIOS).SerialNumber
    $NewComputerName = "$ComputerNamePrefix-$serialNumber"
    Write-Host "Renaming computer to $NewComputerName"
    Rename-Computer -NewName $NewComputerName -Force -Restart:$false
} else {
    $errorMessage = "Error: Unable to retrieve the device serial number. The computer will not be renamed."
    Write-Host $errorMessage
}

# Sets property in registry to disable Windows automatic encryption from start during oobe phase, it does not block Intune bitlocker policy from encrypting devices post enrollment.  
# https://learn.microsoft.com/en-us/windows/security/operating-system-security/data-protection/bitlocker/
Write-Host "Disable Windows Automatic Encryption"
if (-not (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker')) { 
    New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' -Force | Out-Null}
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\BitLocker' -Name 'PreventDeviceEncryption' -Value 1 -PropertyType DWord -Force | Out-Null

# Configure keyboard layout
Write-Host "Configuring keyboard layout to $RegionalLocale"
$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\i8042prt\Parameters'
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
Set-ItemProperty -Path $RegPath -Name "LayerDriver Swedish" -Value "kbd101a.dll" -Type String -Force -ErrorAction SilentlyContinue

# Set keyboard layout via registry
$KbdRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts\$KeyboardLayoutId"
if (-not (Test-Path $KbdRegPath)) {
    New-Item -Path $KbdRegPath -Force | Out-Null
}

# Bypass OOBE and go straight to login screen
Write-Host "Configuring system to skip OOBE"
# Set OOBE as completed
$OOBERegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE'
if (-not (Test-Path $OOBERegistryPath)) {
    New-Item -Path $OOBERegistryPath -Force | Out-Null
}
Set-ItemProperty -Path $OOBERegistryPath -Name 'SetupDisplayedEula' -Value 1 -Type DWord -Force
Set-ItemProperty -Path $OOBERegistryPath -Name 'PrivacyConsentStatus' -Value 1 -Type DWord -Force
Set-ItemProperty -Path $OOBERegistryPath -Name 'SkipMachineOOBE' -Value 1 -Type DWord -Force
Set-ItemProperty -Path $OOBERegistryPath -Name 'SkipUserOOBE' -Value 1 -Type DWord -Force

# Skip network connectivity check (prevents OOBE from asking to connect to internet)
Set-ItemProperty -Path $OOBERegistryPath -Name 'SkipNetworkWizard' -Value 1 -Type DWord -Force

# Force OOBE to not show (sets the system as already configured for local account)
Set-ItemProperty -Path $OOBERegistryPath -Name 'UnattendCreatedUser' -Value 1 -Type DWord -Force

# Disable account setup page (prevents "How would you like to set up this device?" prompt)
$CloudExperiencePath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent\Wireless'
if (-not (Test-Path $CloudExperiencePath)) {
    New-Item -Path $CloudExperiencePath -Force | Out-Null
}
Set-ItemProperty -Path $CloudExperiencePath -Name 'ScoobeOnFirstConnect' -Value 0 -Type DWord -Force

# Disable network setup page
$WirelessPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CloudExperienceHost\Intent'
if (-not (Test-Path $WirelessPath)) {
    New-Item -Path $WirelessPath -Force | Out-Null
}

# Prevent showing OOBE for account setup (domain join or local account choice)
$CloudExperienceHostPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
if (-not (Test-Path $CloudExperienceHostPath)) {
    New-Item -Path $CloudExperienceHostPath -Force | Out-Null
}
Set-ItemProperty -Path $CloudExperienceHostPath -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord -Force

# Disable first logon animation
$ShellRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-ItemProperty -Path $ShellRegistryPath -Name 'EnableFirstLogonAnimation' -Value 0 -Type DWord -Force

# Pre-configure locale to skip region/language selection
$LocalePolicyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language'
Set-ItemProperty -Path $LocalePolicyPath -Name 'InstallLanguage' -Value $InstallLanguageId -Type String -Force -ErrorAction SilentlyContinue

Write-Host "OOBE bypass and regional settings configured."

# Create local admin account

$local_user = @{
    Name        = $LocalUserName
    NoPassword  = $true
    FullName    = $LocalUserFullName
    Description = $LocalUserDescription
}
$user = Get-LocalUser -Name $LocalUserName -ErrorAction SilentlyContinue
if ($null -eq $user) {
    try {
        $user = New-LocalUser @local_user -ErrorAction Stop
        Write-Host "Created new local user '$LocalUserName' without password."
    } catch {
        Write-Warning "Failed to create local user '$LocalUserName': $($_.Exception.Message)"
    }
}
if ($null -ne $user) {
    try {
        $user | Set-LocalUser -PasswordNeverExpires $true
        Add-LocalGroupMember -Group "Administrators" -Member $user.Name -ErrorAction Stop
        Write-Host "Added '$LocalUserName' to Administrators group."
        
        # Set password after user creation (more reliable during OOBE)
        $Password = ConvertTo-SecureString $LocalUserPassword -AsPlainText -Force
        $user | Set-LocalUser -Password $Password
        Write-Host "Password set for '$LocalUserName' account."
        
        # Set regional settings to according to $RegionalLocale for $LocalUserName user
        Write-Host "Configuring regional settings to $RegionalLocale for $LocalUserName user"
        $RegPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Profiles\$($user.SID)\Control Panel\International"
        
        # Load the user registry hive temporarily
        reg load "HKEY_LOCAL_MACHINE\$($user.SID)" "C:\Users\$($user.Name)\NTUSER.DAT" 2>$null
        
        # Set regional locale settings using reg add (more reliable for loaded hives)
        reg add "HKEY_LOCAL_MACHINE\$($user.SID)\Control Panel\International" /v "LocaleName" /d "$RegionalLocale" /f 2>$null
        reg add "HKEY_LOCAL_MACHINE\$($user.SID)\Control Panel\International" /v "sCountry" /d "$RegionalCountry" /f 2>$null
        reg add "HKEY_LOCAL_MACHINE\$($user.SID)\Control Panel\International" /v "sLanguage" /d "$RegionalLanguage" /f 2>$null
        
        # Unload the registry hive
        [gc]::Collect()
        Start-Sleep -Seconds 1
        reg unload "HKEY_LOCAL_MACHINE\$($user.SID)" 2>$null
        
        Write-Host "Regional settings configured for $LocalUserName user."
        
        # Set timezone to according to $TimeZoneId
        Write-Host "Setting timezone to $TimeZoneId"
        Set-TimeZone -Id $TimeZoneId -ErrorAction SilentlyContinue
        Write-Host "Timezone configured."
    } catch {
        Write-Warning "Failed to configure local user '$LocalUserName': $($_.Exception.Message)"
    }
}

# Enable and update Windows Defender
Write-Host "Enabling Windows Defender and updating definitions"
try {
    # Ensure Windows Defender service is running
    $DefenderService = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
    if ($DefenderService.Status -ne 'Running') {
        Write-Host "Starting Windows Defender service"
        Start-Service -Name WinDefend -ErrorAction Stop
    }
    
    # Enable real-time protection
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    
    # Update Windows Defender definitions
    Write-Host "Updating Windows Defender definitions (this may take a moment)"
    Update-MpSignature -ErrorAction Stop
    Write-Host "Windows Defender definitions updated successfully"
    
    # Get current signature version
    $DefenderStatus = Get-MpComputerStatus
    Write-Host "Antivirus signature version: $($DefenderStatus.AntivirusSignatureVersion)"
    Write-Host "Signature last updated: $($DefenderStatus.AntivirusSignatureLastUpdated)"
} catch {
    Write-Warning "Failed to configure Windows Defender: $($_.Exception.Message)"
}

# Configure power settings
Write-Host 'Setting PowerPlan to Balanced'

# Disable sleep, hibernate and monitor standby on AC and DC power
powercfg /setactive 381B4222-F694-41F0-9685-FF5BB260DF2E | Out-Null
powercfg -x -monitor-timeout-ac 0
powercfg -x -monitor-timeout-dc 0
powercfg -x -standby-timeout-ac 0
powercfg -x -standby-timeout-dc 0
powercfg -x -hibernate-timeout-ac 0
powercfg -x -hibernate-timeout-dc 0


# Timing & wrap-up
$EndTime = Get-Date
$RunTimeMinutes = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes, 0)
Write-Host ("End Time: {0}" -f $EndTime.ToString("HH:mm:ss"))
Write-Host "Run Time: $RunTimeMinutes Minutes"
Stop-Transcript

# Reboot after completion
Restart-Computer -Force