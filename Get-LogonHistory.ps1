<#
.SYNOPSIS
Get the logon history of a given computer.

.DESCRIPTION
Creates a remote task (by default, the local one if none is given) to query its history of users that have logged into it.  It can be given multiple computers to query.
#>

param(
    [alias("CN")]
    $ComputerName="localhost",
    [alias("Newest")]
    $Depth=0,
    [alias("AsUser")]
    $UserName
)

$get_eventlog = {
    param($Depth)
    $UserProperty = @{n="User";e={(New-Object System.Security.Principal.SecurityIdentifier $_.ReplacementStrings[1]).Translate([System.Security.Principal.NTAccount])}}
    $TypeProperty = @{n="Action";e={if($_.EventID -eq 7001) {"Logon"} else {"Logoff"}}}
    $TimeProperty = @{n="Time";e={$_.TimeGenerated}}
    $MachineNameProperty = @{n="MachinenName";e={$_.MachineName}}
    if (0 -lt $Depth) {
        Get-EventLog System -Source Microsoft-Windows-Winlogon -Newest $Depth | select $UserProperty,$TypeProperty,$TimeProperty,$MachineNameProperty
    } else {
        Get-EventLog System -Source Microsoft-Windows-Winlogon | select $UserProperty,$TypeProperty,$TimeProperty,$MachineNameProperty
    }
    #Invoke-Expression $GetEventCmd | select $UserProperty,$TypeProperty,$TimeProperty,$MachineNameProperty
}

if (-not ([string]::IsNullOrEmpty($UserName))) {
    $Credentials = Get-Credential -UserName $UserName -Message "Please enter the password for $UserName."
}

foreach ($computer in $ComputerName) {
    if ([string]::IsNullOrEmpty($UserName)) {
        Invoke-Command -ComputerName $computer -ScriptBlock $get_eventlog -ArgumentList $Depth | Format-Table
    } else {
        Invoke-Command -ComputerName $computer -ScriptBlock $get_eventlog -ArgumentList $Depth -Credential $Credentials | Format-Table
    }   
}