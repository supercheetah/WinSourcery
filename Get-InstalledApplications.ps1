<#
.SYNOPSIS
Find out the currently installed applications in a list of computers.

.DESCRIPTION
Queries a given list of computers (pulled from an OU selected from an AD forest by default)
for their current list of installed applications according to the registry (which is faster 
than the WMI method).
#>

param(
    [parameter(Mandatory=$false)]
    [alias("cn")]
    [string[]]$ComputerName,
    [parameter(Mandatory=$false)]
    [string]$OutputCSV="output.csv"
)

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$script_path\lib\TestComputerIsOff.psm1"
Import-Module -Verbose "$script_path\lib\GetUsersOrComputers.psm1"

if ([string]::IsNullOrEmpty($ComputerName)) {
    $computer_list = Get-ComputerListFromOU
} else {
    $computer_list = $ComputerName
}

$credentials = Get-Credential -Message "Use an elevated account (fs or wa):"

$query_inst_list = {
    #credit: http://stackoverflow.com/a/31917048
    try{
        $InstalledSoftware = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*
        $InstalledSoftware += Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*
    } catch {
        Write-warning "Error while trying to retreive installed software from inventory: $($_.Exception.Message)"
    }

    $InstalledMSIs = @()
    foreach ($App in $InstalledSoftware){
        if($App.PSChildname -match "\A\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}\z"){
            $InstalledMSIs += New-Object PSObject -Property @{
                DisplayName = $App.DisplayName;
                DisplayVersion = $App.DisplayVersion;
                Publisher = $App.Publisher;
                InstallDate = $App.InstallDate;
                GUID = $App.PSChildName;
            }
        }
    }
    return $InstalledMSIs
}

$i = 0

$installed_list = @()
$computer_waitlist = @()

foreach ($computer in $computer_list) {
    Write-Progress -Activity "Sending installed programs query to..." -Status $computer -PercentComplete ($i++/($computer_list.Count+$computer_waitlist.Count)*100)
    if (Test-ComputerIsOff $computer) {
        $installed_list += New-Object psobject -Property @{
            DisplayName = "OFFLINE";
            DisplayVersion = "OFFLINE";
            Publisher = "OFFLINE";
            InstallDate = "OFFLINE";
            GUID = "OFFLINE";
            PSComputerName = $computer;
            RunspaceId = "OFFLINE";
            PSSourceJobInstanceId = "OFFLINE"
        }
    } else {
        try {
            Invoke-Command -ComputerName $computer -Credential $credentials -ScriptBlock $query_inst_list -AsJob -JobName $computer
            $computer_waitlist += $computer
        } catch {
            $installed_list += New-Object psobject -Property @{
                DisplayName = ("ERROR: {0}" -f $_.Exception.Message);
                DisplayVersion = "ERROR";
                Publisher = "ERROR";
                InstallDate = "ERROR";
                GUID = "ERROR";
                PSComputerName = $computer;
                RunspaceId = "ERROR";
                PSSourceJobInstanceId = "ERROR"
            }
        }
    }
}

foreach ($computer in $computer_waitlist) {
    Write-Progress -Activity "Waiting for results from:" -Status $computer -PercentComplete ($i++/($computer_list.Count+$computer_waitlist.Count)*100)
    try {
        $job =  Receive-Job -Name $computer -Wait -AutoRemoveJob -WriteJobInResults
        if ($job.GetType().Name -eq "PSRemotingJob") { #probably an error
            throw $job.ChildJobs[0].JobStateInfo.Reason
        }
        for ($j = 1; $j -lt $job.Count; $j++) {
            $installed_list += $job[$j]
        }
    } catch {
        $installed_list += New-Object psobject -Property @{
            DisplayName = ("ERROR: {0}" -f $_.Exception.Message);
            DisplayVersion = "ERROR";
            Publisher = "ERROR";
            InstallDate = "ERROR";
            GUID = "ERROR";
            PSComputerName = $computer;
            RunspaceId = "ERROR";
            PSSourceJobInstanceId = "ERROR"
        }
    }
}

$installed_list | Export-Csv -NoTypeInformation $OutputCSV
$installed_list | ogv