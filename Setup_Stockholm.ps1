# OSDCloud SetupComplete.ps1; Location: C:\Windows\Setup\Scripts\Setup_Stockholm.ps1
# Logs setup process, imports OSD modules, sets power plan, runs custom SetupComplete.cmd, and reboots when finished.

##================================================
## MARK: Configuration Variables
##================================================
$LocalUserName = 'EDU'
$LocalUserPassword = 'Assa#26144'
$LocalUserFullName = 'Education User'
$LocalUserDescription = 'Local administrator account for EDU purposes'
$ComputerNamePrefix = 'SESTV'
$RegionalLocale = 'sv-SE'
$RegionalCountry = 'Sweden'
$RegionalLanguage = 'SVE'
$TimeZoneId = 'W. Europe Standard Time'

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

# Renaming to SESTV-[serialnumber]
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

# Disable first logon animation
$ShellRegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-ItemProperty -Path $ShellRegistryPath -Name 'EnableFirstLogonAnimation' -Value 0 -Type DWord -Force

Write-Host "OOBE bypass configured."

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
        
        # Set regional settings to Swedish for EDU user
        Write-Host "Configuring regional settings to $RegionalLocale for $LocalUserName user"
        $RegPath = "HKU:\$($user.SID)\Control Panel\International"
        
        # Load the user registry hive temporarily
        reg load "HKU\$($user.SID)" "C:\Users\$($user.Name)\NTUSER.DAT" 2>$null
        
        # Set Swedish locale settings
        Set-ItemProperty -Path $RegPath -Name "LocaleName" -Value $RegionalLocale -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $RegPath -Name "sCountry" -Value $RegionalCountry -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $RegPath -Name "sLanguage" -Value $RegionalLanguage -ErrorAction SilentlyContinue
        
        # Unload the registry hive
        [gc]::Collect()
        Start-Sleep -Seconds 1
        reg unload "HKU\$($user.SID)" 2>$null
        
        Write-Host "Regional settings configured for $LocalUserName user."
        
        # Set timezone to W. Europe Standard Time (Stockholm/Sweden)
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