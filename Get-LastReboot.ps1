<#
.SYNOPSIS
Query when a remote computer was last rebooted.

.DESCRIPTION
Sends a task to a remote computer to find out its last boot time.
#>
# Rene Horn, the.rhorn@gmail.com

param (
    [parameter(Mandatory=$false)]
    [alias("cn")]
    [string]$ComputerName="."
)

$get_last_boot_time = {
    # shamelessly stolen from here: http://blogs.technet.com/b/heyscriptingguy/archive/2013/03/27/powertip-get-the-last-boot-time-with-powershell.aspx
    if (3 -le $PSVersionTable.PSVersion.Major) {
        Get-CimInstance -ClassName win32_operatingsystem | select csname, lastbootuptime
    } else {
        Get-WmiObject win32_operatingsystem | select csname, @{LABEL='LastBootUpTime';EXPRESSION={$_.ConverttoDateTime($_.lastbootuptime)}}
    }
}

Invoke-Command -ComputerName $ComputerName -ScriptBlock $get_last_boot_time