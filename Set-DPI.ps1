<#
.SYNOPSIS
Allows a user to set a particular DPI (zoom) level.

.DESCRIPTION
This was created for restricted desktops so that the users on them can have a simple shortcut that sets the DPI or zoom level for them.
#>

param(
    [parameter(Mandatory=$true)]
    [int]$Value
)

[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "LogPixels" -Value $Value

$message = "You need to log out completely, and then back in for these settings too take effect. Log off now?"
$caption = "Log out?"
$response = [System.Windows.Forms.MessageBox]::Show($message, $caption, "YesNo", "Warning", "Button1", 0)

if ($response -eq "Yes") {
    & C:\WINDOWS\system32\logoff.exe
}