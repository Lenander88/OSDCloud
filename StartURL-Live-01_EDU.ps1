##================================================
## MARK: Variables
##================================================
    $backgroundColor = "Black"
    $foregroundColor = "Green"
    # Path to CSV and URL
    $csvPath = ".\EDU.csv"
    $csvUrl = 'https://raw.githubusercontent.com/Lenander88/OSDCloud/dev/EDU.csv'
    # Write-Host texts before ComboBox
    $startText = "Starting EDU Build Selection"
    # ComboBox action text
    $selectText = "Select EDU Build"
    # SetupComplete folder path
    $setupPath = 'C:\OSDCloud\Scripts\SetupComplete'
    # Url to SetupComplete.cmd

##=======================================================================
##   [PreOS] Update Module
##=======================================================================
Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor "Updating OSD PowerShell Module"
Install-Module OSD -Force

Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor "Importing OSD PowerShell Module"
Import-Module OSD -Force   


##=======================================================================
##   [PreOS] Params
##=======================================================================
$Params = @{
    OSVersion = "Windows 11"
    OSBuild = "24H2"
    OSEdition = "Pro"
    OSLanguage = "en-us"
    OSLicense = "Retail"
    ZTI = $true
    Firmware = $true
}

##=======================================================================
##   [PreOS] Group all Add-Type calls together for clarity
##=======================================================================
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

##=======================================================================
##   [PreOS] EDU Build Selection
##=======================================================================
Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor $startText
Start-Sleep -Seconds 5

# Path to CSV file
if (!(Test-Path $csvPath) -or ((Get-Item $csvPath).LastWriteTime -lt (Get-Date).AddDays(-1))) {
    Invoke-WebRequest -Uri $csvUrl -OutFile $csvPath
}
# Import CSV
$options = Import-CSV $csvPath

# Create Form
$form = New-Object System.Windows.Forms.Form
$form.Text = $selectText
$form.Size = New-Object System.Drawing.Size(300,150)
$form.StartPosition = "CenterScreen"

# Create ComboBox
$comboBox = New-Object System.Windows.Forms.ComboBox
$comboBox.Location = New-Object System.Drawing.Point(50,20)
$comboBox.Size = New-Object System.Drawing.Size(200,20)
$comboBox.DropDownStyle = 'DropDownList'  # Prevent typing, only select

# Populate ComboBox with OptionName from CSV
foreach ($item in $options) {
    $comboBox.Items.Add($item.OptionName)
}

# Add ComboBox to Form
$form.Controls.Add($comboBox)

# Create OK Button
$okButton = New-Object System.Windows.Forms.Button
$okButton.Text = "OK"
$okButton.Location = New-Object System.Drawing.Point(100,60)

# OK Button Click Event Handler
$okButtonClickHandler = {
    $selectedOption = $comboBox.SelectedItem
    if ($selectedOption) {
        # Assign corresponding Value to $edu (hidden from user)
        $script:edu = ($options | Where-Object { $_.OptionName -eq $selectedOption }).Value
        $form.Close()
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select an option.")
    }
}
 # Attach Click Event Handler
$okButton.Add_Click($okButtonClickHandler)

# Add OK Button to Form
$form.Controls.Add($okButton)

# Show Form
$form.ShowDialog()

##=======================================================================
##   [OS] Start-OSDCloud with Params
##=======================================================================
Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor "Start OSDCloud"
Start-OSDCloud @Params

##=======================================================================
##   [PostOS] SetupComplete CMD Command Line
##=======================================================================

Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor "Stage SetupComplete"

# Ensure PSWindowsUpdate is staged for post-boot use
Save-Module -Name PSWindowsUpdate -Path 'C:\Program Files\WindowsPowerShell\Modules' -Force

# Ensure SetupComplete folder exists
if (-not (Test-Path $setupPath)) {
    New-Item -Path $setupPath -ItemType Directory -Force | Out-Null
}

# Run the selected EDU command (from ComboBox selection)
Invoke-Expression $edu

# Download SetupComplete.cmd
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Lenander88/OSDCloud/dev/SetupComplete.cmd' `
    -OutFile "$setupPath\SetupComplete.cmd"

# Download Install-LCU.ps1
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Lenander88/OSDCloud/dev/Install-LCU.ps1' `
    -OutFile "$setupPath\Install-LCU.ps1"

##=======================================================================
##   Restart-Computer
##=======================================================================   
    Write-Host -BackgroundColor $backgroundColor -ForegroundColor $foregroundColor "Restart in 20 seconds"
    Start-Sleep -Seconds 20
    wpeutil reboot
