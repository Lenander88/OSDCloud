# OSDCloud SetupComplete.ps1; Location: C:\Windows\Setup\Scripts\Setup_Stockholm.ps1
# Logs setup process, imports OSD modules, sets power plan, runs custom SetupComplete.cmd, and reboots when finished.

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
    $NewComputerName = "SESTV-$serialNumber"
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

# Create local admin account

$Password = ConvertTo-SecureString "Assa#26144" -AsPlainText -Force
$local_user = @{
    Name     = 'EDU'
    Password = $Password
    NoPassword = $false
    FullName = 'Education User'
    Description = 'Local administrator account for EDU purposes'
}
$user = Get-LocalUser -Name 'EDU' -ErrorAction SilentlyContinue
if ($null -eq $user) {
    try {
        $user = New-LocalUser @local_user -ErrorAction Stop
        Write-Host "Created new local user 'EDU'."
    } catch {
        Write-Warning "Failed to create local user 'EDU': $($_.Exception.Message)"
    }
}
if ($null -ne $user) {
    try {
        $user | Set-LocalUser -PasswordNeverExpires $true
        Add-LocalGroupMember -Group "Administrators" -Member $user.Name -ErrorAction Stop
    } catch {
        Write-Warning "Failed to configure local user 'EDU': $($_.Exception.Message)"
    }
}

# Configure power settings
Write-Host 'Setting PowerPlan to Balanced'

# Disable sleep, hibernate and monitor standby on AC and DC power
powercfg /setactive 381B4222-F694-41F0-9685-FF5BB260DF2E | Out-Null
$powercfgCommands = @(
    "-x -monitor-timeout-ac 0",
    "-x -standby-timeout-ac 0",
    "-x -standby-timeout-dc 0",
    "-x -hibernate-timeout-ac 0",
    "-x -hibernate-timeout-dc 0"
)

foreach ($cmd in $powercfgCommands) {
    powercfg $cmd
}


# Timing & wrap-up
$EndTime = Get-Date
$RunTimeMinutes = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes, 0)
Write-Host ("End Time: {0}" -f $EndTime.ToString("HH:mm:ss"))
Write-Host "Run Time: $RunTimeMinutes Minutes"
Stop-Transcript

# Reboot after completion
Restart-Computer -Force