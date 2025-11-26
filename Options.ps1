###################Load Assembly for creating form & button######
  
[void][System.Reflection.Assembly]::LoadWithPartialName( "System.Windows.Forms")
[void][System.Reflection.Assembly]::LoadWithPartialName( "Microsoft.VisualBasic")
  
  
#####Define the form size & placement
  
$form = New-Object "System.Windows.Forms.Form";
$form.Width = 500;
$form.Height = 190;
$form.Text = $title;
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen;
$form.ControlBox = $True
  
  
##############Define text label2
  
$textLabel2 = New-Object "System.Windows.Forms.Label";
$textLabel2.Left = 25;
$textLabel2.Top = 80;
  
$textLabel2.Text = $WF;
  
  
############Define text box2 for input
  
$cBox2 = New-Object "System.Windows.Forms.combobox";
$cBox2.Left = 150;
$cBox2.Top = 80;
$cBox2.width = 200;
  
  
###############"Add descriptions to combo box"##############

Invoke-WebRequest -Uri “https://raw.githubusercontent.com/Lenander88/L88/main/Profiles.csv” -Outfile “C:\temp\Profiles.csv” 
Import-CSV "C:\temp\Profiles.csv" | ForEach-Object {
    $cBox2.Items.Add($_.Profiles)
      
}
  
  
#############define OK button
$button = New-Object "System.Windows.Forms.Button";
$button.Left = 360;
$button.Top = 45;
$button.Width = 100;
$button.Text = “OK”;
$Button.Cursor = [System.Windows.Forms.Cursors]::Hand
$Button.Font = New-Object System.Drawing.Font("Comic Sans",12,[System.Drawing.FontStyle]::BOLD)
############# This is when you have to close the form after getting values
$eventHandler = [System.EventHandler]{
$cBox2.Text;
$form.Close();};
$button.Add_Click($eventHandler) ;
  
#############Add controls to all the above objects defined
$form.Controls.Add($button);
$form.Controls.Add($textLabel2);
$form.Controls.Add($cBox2);
#$ret = $form.ShowDialog();
  
#################return values
$button.add_Click({
      
    #Set-Variable -Name locationResult -Value $combobox1.selectedItem -Force -Scope Script # Use this
    $script:locationResult = $cBox2.selectedItem # or this to retrieve the user selection
})
  
$form.Controls.Add($button)
$form.Controls.Add($cBox2)
  
$form.ShowDialog()
  
$grouptag = $script:locationResult
Write-Output $grouptag