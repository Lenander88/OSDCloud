##=======================================================================
##   Mark: Variables and Constants
##=======================================================================
# --- External URLs ---
$UriLogicApp = 'https://prod-145.westus.logic.azure.com:443/workflows/dadfcaca1bcc4b069c998a99e82ee728/triggers/manual/paths/invoke?api-version=2016-06-01&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=n0urWoGWa2OXN-4ba0U7UwfEM8i9vwTuSHx2PrSVtvU'
$UriPCPKsp = 'https://github.com/Lenander88/OSDCloud/raw/dev/PCPKsp.dll'
$UriOA3Config = 'https://github.com/Lenander88/OSDCloud/raw/dev/OA3.cfg'
$UriOA3Tool = 'https://github.com/Lenander88/OSDCloud/raw/dev/oa3tool.exe'
$UriGroupTags = 'https://github.com/Lenander88/OSDCloud/raw/dev/grouptags.csv'
# --- SetupComplete Script URLs ---
$UriSetupComplete = 'https://github.com/dwp-lab/OSDCloud/raw/main/SetupComplete.ps1'
$UriSetupCompleteCmd = 'https://github.com/dwp-lab/OSDCloud/raw/main/SetupComplete.cmd'
$UriInstallLCU = 'https://github.com/dwp-lab/OSDCloud/raw/main/Install-LCU.ps1'

# --- Status and Initialization Messages ---
$MsgStartOSDCloud = "Start OSDCloud ZTI"
$MsgStartAutopilotVerification = "Start AutoPilot Verification"
$MsgUpdateOSDModule = "Update OSD PowerShell Module"
$MsgImportOSDModule = "Import OSD PowerShell Module"
$MsgStartOSDCloudDeploy = "Start OSDCloud"
$MsgStageSetupComplete = "Stage SetupComplete"
$MsgRestartIn20Seconds = "Restart in 20 seconds"

# --- Error and Warning Messages ---
$MsgSerialNumberNotFound = "We were unable to locate the serial number of your device, so the process cannot proceed. The computer will shut down when this window is closed."
$MsgAutopilotNotReady = "You cannot continue because the device is not ready for Windows AutoPilot. The HWHash has been generated and placed on the USB-stick, upload HWHash, reinsert USB-stick and click OK to start deployment."

# --- UI Dialog Messages ---
$MsgGroupTagTitle = "Digital Workplace Group Tag"
$MsgGroupTagLabel = "Group tag"
$MsgOKButton = "OK"
$MsgOSDCloudTitle = "OSDCloud"
$MsgHWHashTitle = "HWHash"
$MsgWarning = "Warning"
$MsgSelectValidOption = "Please select a valid group tag."

# --- UI Styling ---
$BackgroundColor = "Black"
$ForegroundColor = "Green"

# --- File Paths and Settings ---
$GroupTagsCSVPath = ".\grouptags.csv"
$OA3XMLPath = ".\OA3.xml"
$AutopilotHWIDPath = ".\AutopilotHWID.csv"
$PSWindowsUpdateModulePath = 'C:\Program Files\WindowsPowerShell\Modules'
$SetupCompleteOutPath = 'C:\Windows\Setup\Scripts\SetupComplete.ps1'
$SetupCompleteCmdOutPath = 'C:\OSDCloud\Scripts\SetupComplete\SetupComplete.cmd'
$InstallLCUOutPath = 'C:\OSDCloud\Scripts\SetupComplete\Install-LCU.ps1'

##=======================================================================
##   [PreOS] Params
##=======================================================================
$Params = @{
    OSVersion = "Windows 11"
    OSBuild = "24H2" # "24H2" | "25H2"
    OSEdition = "Enterprise" # "Enterprise" | "Pro"
    OSLanguage = "en-us"
    OSLicense = "Retail" # "Volume" | "Retail"
    ZTI = $true
    Firmware = $true
}


##=======================================================================
##   [PreOS] Script Start
##=======================================================================
Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStartOSDCloud
Start-Sleep -Seconds 5

##=======================================================================
##   [PreOS] Initialize Assembly Types
##=======================================================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

##=======================================================================
##   [PreOS] Serial Number Verification
##=======================================================================
$bodyMessage = [PSCustomObject] @{}; Clear-Variable serialNumber -ErrorAction:SilentlyContinue
$serialNumber = Get-CimInstance -ClassName Win32_BIOS | Select-Object -ExpandProperty SerialNumber

if ($serialNumber) {

    $bodyMessage | Add-Member -MemberType NoteProperty -Name "serialNumber" -Value $serialNumber

} else {

    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor Red $MsgSerialNumberNotFound
    [System.Windows.Forms.MessageBox]::Show($MsgSerialNumberNotFound, $MsgOSDCloudTitle, $MsgOKButton, 'Error') | Out-Null
    wpeutil shutdown
}

##=======================================================================
##   [PreOS] AutoPilot Verification
##=======================================================================
Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStartAutopilotVerification
$body = $bodyMessage | ConvertTo-Json -Depth 5; $uri = $UriLogicApp
$result = Invoke-RestMethod -Uri $uri -Method POST -Body $body -ContentType "application/json; charset=utf-8" -UseBasicParsing    

##=======================================================================
##   [PreOS] AutoPilot Not Ready - Hardware Hash Generation
##=======================================================================
if ($result.Response -eq 0) {

    Invoke-WebRequest -Uri $UriPCPKsp -OutFile X:\Windows\System32\PCPKsp.dll
    rundll32 X:\Windows\System32\PCPKsp.dll,DllInstall

    Invoke-WebRequest -Uri $UriOA3Config -OutFile OA3.cfg
    Invoke-WebRequest -Uri $UriOA3Tool -OutFile oa3tool.exe
    Remove-Item $OA3XMLPath -ErrorAction:SilentlyContinue
    .\oa3tool.exe /Report /ConfigFile=.\OA3.cfg /NoKeyCheck

    ##===================================================================
    ##   [PreOS] Group Tag Selection Dialog
    ##===================================================================
    if (Test-Path $OA3XMLPath) {
        
        # Download and cache group tags CSV
        if (!(Test-Path $GroupTagsCSVPath) -or ((Get-Item $GroupTagsCSVPath).LastWriteTime -lt (Get-Date).AddDays(-1))) {
            Invoke-WebRequest -Uri $UriGroupTags -OutFile $GroupTagsCSVPath
        }
        
        # Import CSV
        $groupTagOptions = Import-CSV $GroupTagsCSVPath
        
            # Create Form
            $form = New-Object System.Windows.Forms.Form
            $form.Text = $MsgGroupTagTitle
            $form.Size = New-Object System.Drawing.Size(350, 150)
            $form.StartPosition = "CenterScreen"
            
            # Create Label
            $label = New-Object System.Windows.Forms.Label
            $label.Text = $MsgGroupTagLabel
            $label.Location = New-Object System.Drawing.Point(20, 20)
            $label.Size = New-Object System.Drawing.Size(100, 20)
            $form.Controls.Add($label)
            
            # Create ComboBox
            $comboBox = New-Object System.Windows.Forms.ComboBox
            $comboBox.Location = New-Object System.Drawing.Point(120, 20)
            $comboBox.Size = New-Object System.Drawing.Size(200, 20)
            $comboBox.DropDownStyle = 'DropDownList'  # Prevent typing, only select
            
            # Populate ComboBox with grouptags from CSV
            foreach ($item in $groupTagOptions) {
                $comboBox.Items.Add($item.OptionName)
            }
            
            # Add ComboBox to Form
            $form.Controls.Add($comboBox)
            
            # Create OK Button
            $okButton = New-Object System.Windows.Forms.Button
            $okButton.Text = $MsgOKButton
            $okButton.Location = New-Object System.Drawing.Point(120, 60)
            $okButton.Cursor = [System.Windows.Forms.Cursors]::Hand
            
            # OK Button Click Event Handler
            $okButtonClickHandler = {
                $selectedOption = $comboBox.SelectedItem
                if ($selectedOption) {
                    # Assign corresponding value to $grouptag (hidden from user)
                    $global:grouptag = ($groupTagOptions | Where-Object { $_.OptionName -eq $selectedOption }).Value
                    $form.Close()
                } else {
                    [System.Windows.Forms.MessageBox]::Show($MsgSelectValidOption)
                }
            }
            $okButton.Add_Click($okButtonClickHandler)
            
            $form.Controls.Add($okButton)
            
            # Show Form
            $form.ShowDialog()

        ##=================================================================
        ##   [PreOS] Hardware Hash Export
        ##=================================================================
        [xml]$xmlhash = Get-Content -Path $OA3XMLPath
        $hash = $xmlhash.Key.HardwareHash

        $computers = @(); $product = ""

        $c = New-Object psobject -Property @{
            "Device Serial Number" = $serialNumber
            "Windows Product ID" = $product
            "Hardware Hash" = $hash
            "Group Tag" = $grouptag
        }

        $computers += $c
        $computers | Select-Object "Device Serial Number", "Windows Product ID", "Hardware Hash", "Group Tag" | ConvertTo-CSV -NoTypeInformation | ForEach-Object {$_ -replace '"',''} | Out-File $AutopilotHWIDPath
        
        # Copy to USB media
        $usbMedia = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 2"
        foreach ($disk in $usbMedia) {
            Copy-Item -Path $AutopilotHWIDPath -Destination "$($disk.DeviceID)\$($serialNumber).csv" -Force -ErrorAction:SilentlyContinue
        }
        Copy-Item -Path $AutopilotHWIDPath -Destination "C:\$($serialNumber).csv" -Force -ErrorAction:SilentlyContinue
    }

    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor Yellow $MsgAutopilotNotReady
    [System.Windows.Forms.MessageBox]::Show($MsgAutopilotNotReady, $MsgHWHashTitle, $MsgOKButton, $MsgWarning) | Out-Null
    
    ##===================================================================
    ##   [PreOS] Module Installation
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgUpdateOSDModule
    Install-Module OSD -Force -SkipPublisherCheck

    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgImportOSDModule
    Import-Module OSD -Force

    ##===================================================================
    ##   [PreOS] OS Installation
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStartOSDCloudDeploy
    Start-OSDCloud @Params

    ##===================================================================
    ##   [PreOS] Stage SetupComplete Scripts
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStageSetupComplete
    Save-Module -Name PSWindowsUpdate -Path $PSWindowsUpdateModulePath -Force # Stage PSWindowsUpdate so it's available after first boot (no PSGallery needed in pre-OOBE)
    Invoke-WebRequest -Uri $UriSetupComplete -OutFile $SetupCompleteOutPath # Runs automatically after setup complete, during pre-OOBE. Calls the custom SetupComplete.cmd
    Invoke-WebRequest -Uri $UriSetupCompleteCmd -OutFile $SetupCompleteCmdOutPath # Custom SetupComplete.cmd, triggered by SetupComplete.ps1. Calls Install-LCU.ps1
    Invoke-WebRequest -Uri $UriInstallLCU -OutFile $InstallLCUOutPath # Installs the latest SSU/LCU + critical updates
   
##=======================================================================
##   [PreOS] Restart System
##=======================================================================
Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgRestartIn20Seconds
Start-Sleep -Seconds 20
wpeutil reboot

##=======================================================================
##   [PostOS] Module Installation
##=======================================================================
} else {

    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgUpdateOSDModule
    Install-Module OSD -Force -SkipPublisherCheck

    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgImportOSDModule
    Import-Module OSD -Force

    ##===================================================================
    ##   [PostOS] OS Installation
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStartOSDCloudDeploy
    Start-OSDCloud @Params

    ##===================================================================
    ##   [PostOS] Stage SetupComplete Scripts
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgStageSetupComplete
    Save-Module -Name PSWindowsUpdate -Path $PSWindowsUpdateModulePath -Force # Stage PSWindowsUpdate so it's available after first boot (no PSGallery needed in pre-OOBE)
    Invoke-WebRequest -Uri $UriSetupComplete -OutFile $SetupCompleteOutPath # Runs automatically after setup complete, during pre-OOBE. Calls the custom SetupComplete.cmd
    Invoke-WebRequest -Uri $UriSetupCompleteCmd -OutFile $SetupCompleteCmdOutPath # Custom SetupComplete.cmd, triggered by SetupComplete.ps1. Calls Install-LCU.ps1
    Invoke-WebRequest -Uri $UriInstallLCU -OutFile $InstallLCUOutPath # Installs the latest SSU/LCU + critical updates

    ##===================================================================
    ##   [PostOS] Restart System
    ##===================================================================
    Write-Host -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor $MsgRestartIn20Seconds
    Start-Sleep -Seconds 20
    wpeutil reboot
}
