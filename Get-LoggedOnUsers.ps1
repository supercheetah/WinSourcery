<#
.SYNOPSIS
Query any currently logged on users from a list of computers (currently obtained from OU in an AD forest).

.DESCRIPTION
This will query all the currently logged on users in an Organizational Unit chosen from within an Active Directory forest.
#>
$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$script_path\lib\TestComputerIsOff.psm1"
Import-Module -Verbose "$script_path\lib\GetUsersOrComputers.psm1"

$computer_list = Get-ComputerListFromOU

$credentials = Get-Credential -Message "Use an elevated account for your credentials (fs or wa):"

$computer_results = @()

function Create-ComputerLogonObj([string]$ComputerName, [string]$Username)
{
    return New-Object psobject -Property @{
        "Hostname" = $ComputerName
        "Username" = $Username
    }
}

$i = 0
$computer_waitlist = @()

$get_userlogons = {
    try {
        $sessions = query session
        $logon = $sessions | Select-String "rdp-tcp#"
        if (-not $logon) {
            $logon = $sessions | Select-String "console"
        }
        return (
        $logon.ToString() -split "\s+")[2]
    } catch {
        throw $_
    }
}

foreach ($computer in $computer_list) {
    Write-Progress -Activity "Sending login query to..." -Status $computer -PercentComplete ($i++/($computer_list.Count+$computer_waitlist.Count)*100)
    if (Test-ComputerIsOff $computer) {
        $computer_results += Create-ComputerLogonObj $computer "OFFLINE"
    } else {
        try {
            Invoke-Command -ComputerName $computer -Credential $credentials -ScriptBlock $get_userlogons -AsJob -JobName $computer
            $computer_waitlist += $computer
        } catch {
            $computer_results += Create-ComputerLogonObj $computer "UNREACHABLE"
        }
    }
}

foreach ($computer in $computer_waitlist) {
    Write-Progress -Activity "Waiting on..." -Status $computer -PercentComplete ($i++/($computer_list.Count+$computer_waitlist.Count)*100)
    try {
        $job = Receive-Job -Name $computer -Wait -AutoRemoveJob -WriteJobInResults
        if ($job.GetType().Name -eq "PSRemotingJob") { #probably an error
            throw $job.ChildJobs[0].JobStateInfo.Reason
        } 
        $computer_results += Create-ComputerLogonObj $computer $job[1]
    } catch {
        $computer_results += Create-ComputerLogonObj $computer ("ERROR: {0}" -f $_.Exception.Message)
    }
}

$computer_results | Out-GridView