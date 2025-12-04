# Install-LCU.ps1; Location: C:\OSDCloud\Scripts\SetupComplete\Install-LCU.ps1
# Installs latest SSU/LCU + critical updates (max 3 retries). Does not auto-reboot during install; reboot handled separately.

Start-Sleep -Seconds 10
# Install-Module PSWindowsUpdate -Force
Import-Module PSWindowsUpdate -Force

# Pull latest SSU/LCU + critical updates - targeted for speed during OOBE
# Only install Security Updates and Critical Updates (skip optional Updates)
$tries = 0
while ($tries -lt 3) {
  try {
    Get-WindowsUpdate -MicrosoftUpdate -Category "Security Updates","Critical Updates" -AcceptAll -Install -IgnoreReboot
    break
  } catch {
    $tries++
    Start-Sleep -Seconds 60
  }

}