<# 
.SYNOPSIS
Gets the CDP information from a computer(s).

.DESCRIPTION
Attempts to get the CDP information from a computer or a list of them (it will ask for an OU from an AD forest if none is provided.)
It automatically downloads tcpdump.exe if it's not already on a computer.  The results are put into a given CSV file (see parameters,
output.csv by default), and then shown in grid view.

.NOTES
Author: Rene Horn, the.rhorn@gmail.com
#>

param(
    [parameter(Mandatory=$false)]
    [alias("cn")]
    [string[]]$ComputerList,
    [parameter(Mandatory=$false)]
    [alias("as")]
    [string]$Credential,
    [parameter(Mandatory=$false)]
    [string]$OutputCSV="output.csv",
    [parameter(Mandatory=$false)]
    [switch]$RawPacket,
    [parameter(Mandatory=$false)]
    [alias("dn")]
    [int]$DeviceNumber,
    [parameter(Mandatory=$false)]
    [switch]$ComputersFromOU,
    [parameter(Mandatory=$false)]
    [switch]$ShowWarnings,
    [parameter(Mandatory=$false)]
    [switch]$ShowErrors
)

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$script_path\lib\TestComputerIsOff.psm1"
Import-Module -Verbose "$script_path\lib\GetUsersOrComputers.psm1"

if (-not $ComputerList) {
    $ComputerList = Get-ComputerListFromOU
}

$run_tcpdump = {

    param($DeviceNumber, $ShowWarnings, $ShowErrors, $RawPacket)

    function Unzip-File($file, $destination, $filter)
    {
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($file)
        foreach($item in $zip.items()) {
            if ($item.Path -imatch $filter) {
                $shell.NameSpace($destination).CopyHere($item)
            }
        }
    }

    function Get-TCPDump
    {
        $tcpdump_zip = "$env:SystemRoot\temp\tcpdump.zip"
        $tcpdump_url = "https://www.microolap.com/downloads/tcpdump/tcpdump_trial_license.zip"
        if (3 -le $PSVersionTable.PSVersion.Major) {
            Invoke-WebRequest -Uri $tcpdump_url -OutFile $tcpdump_zip
        } else {
            $downloader = New-Object System.Net.WebClient
            $downloader.DownloadFile($tcpdump_url, $tcpdump_zip)
        }
        Unzip-File $tcpdump_zip "$env:systemroot\system32" "tcpdump.exe"
        Remove-Item $tcpdump_zip
    }

    function Get-DeviceID([string[]]$cdp)
    {
        $devid = ($cdp|Select-String "Device-ID") -replace "[^']+'([^']+)'",'$1'
        if (-not $devid) {
            $devid = (($cdp|Select-String "System Name") -split ":\s+")[-1]
        }

        if (-not $devid) {
            $devid = "MISSING"
        }

        return $devid
    }

    function Get-PortDescript([string[]]$cdp)
    {
        $portdesc = ($cdp|Select-String "Port-ID") -replace "[^']+'([^']+)'",'$1'
        if (-not $portdesc) {
            $portdesc = (($cdp|Select-String "Port Description") -split ":\s+")[-1]
        }

        if (-not $portdesc) {
            $portdesc = "MISSING"
        }

        return $portdesc
    }

    function Get-VLAN([string[]]$cdp)
    {
        $vlan = (($cdp|Select-String "VLAN") -split ":\s*")[-1]
        if(-not $vlan) {
            $vlan = (($cdp|Select-String "PVID") -split ":\s+")[-1]
        }

        if (-not $vlan) {
            $vlan = "MISSING"
        }

        return $VLAN
    }

    function Get-Duplex([string[]]$cdp)
    {
        $duplex = (($cdp|Select-String "Duplex") -split ":\s*")[-1]
        if (-not $duplex) {
            $duplex = "MISSING"
        }

        return $duplex
    }

    function Get-SwitchIP([string[]]$cdp)
    {
        # Yeah, it's completely convoluted, I know.
        $sw_ip = ((($cdp|Select-String "Management Address.+IPv") -split ":\s*")[-1]).trim().split()[-1]
        if (-not $sw_ip) {
            $sw_ip = "MISSING"
        }

        return $sw_ip
    }

    function Get-VTP([string[]]$cdp)
    {
        $vtp = ($cdp|Select-String "VTP") -replace "[^']+'([^']+)'",'$1'
        if (-not $vtp) {
            $vtp = "MISSING"
        }

        return $vtp
    }

    try {
        $tcpdump_exe = (Get-Command tcpdump -ErrorAction Stop).Path
    } catch {
        Get-TCPDump
    }
    $devices = ""
    $tcpdump_stdout = "$env:SystemRoot\temp\tcpdump_stdout.txt"
    $tcpdump_stderr = "$env:SystemRoot\temp\tcpdump_stderr.txt"
    if ($DeviceNumber -eq 0) {
        $devices = & tcpdump.exe -D 2> $tcpdump_stderr | where {$_ -match '^[1-9]+\.\\Device\\{[^}]+}'}
        # Yes, this won't work if the number of devices is in the double digits.
        if ($devices -and ($devices.GetType().Name -eq "String")) {
            # Only one device on this machine, we'll assume that it's the only one to use.
            $DeviceNumber = $devices[0] 
        } else {
            $err = Get-Content $tcpdump_stderr | Select-String -pattern "C:\\.+tcpdump.exe.*"
            $switch_info =New-Object psobject -Property @{
                ComputerName = $env:COMPUTERNAME
                DeviceID = ("ERROR: {0}" -f $err)
                PortID = "ERROR"
                VLAN = "ERROR"
                PortDuplex = "ERROR"
                SwitchIPAddress = "ERROR"
                VTPMgmtDomain = "ERROR"
                MACAddress = "ERROR"
                IPAddress = "ERROR"
                Domain = "ERROR"
                Gateway = "ERROR"
            }
            return $switch_info
        }
    }
    $dev_desc = $devices -replace "[^(]+[(]([^)]+).*",'$1'
    $dev_info = Get-WmiObject -Class win32_networkadapter -Filter ("Name='{0}'" -f $dev_desc)
    $dev_conf = Get-WmiObject -Class win32_networkadapterconfiguration -Filter ("Description='{0}'" -f $dev_desc)
    $tcpdump_args = @("-i","$DeviceNumber","-nn","-v","-s","1500","-c","1",'"(ether[12:2]==0x88cc or ether[20:2]==0x2000)"')
    #Write-Host "starting tcpdump"
    $tcpdump_proc = Start-Process -NoNewWindow -FilePath $tcpdump_exe -ArgumentList $tcpdump_args -PassThru -RedirectStandardOutput $tcpdump_stdout -RedirectStandardError $tcpdump_stderr
    #Write-Host "tcpdump running..."
    for ($i = 60; $i -ge 1; $i--) {
        if ($tcpdump_proc.HasExited) {
            break
        }
        #Write-Progress -Activity "Watching the packets..." -Status "Waiting for CDP packet" -SecondsRemaining $i
        Start-Sleep -Seconds 1
    }
    #Write-Host "tcpdump exited"
    if ($tcpdump_proc.HasExited) {
        $allgood = $true
        $cdp = Get-Content $tcpdump_stdout
        #Write-Host "cdp content: $cdp"
        #Remove-Item $tcpdump_stdout
        if (-not $cdp) {
            $cdp = Get-Content $tcpdump_stderr
            $allgood = $false
            #Write-Host "error content: $cdp"
        }
        
        #Remove-Item $tcpdump_stderr

        if ($RawPacket) {
            return $cdp
        } elseif ($allgood) {
            $switch_info = New-Object psobject -Property @{
                ComputerName = $env:COMPUTERNAME
                DeviceID = Get-DeviceID $cdp
                PortID = Get-PortDescript $cdp
                VLAN = Get-VLAN $cdp
                PortDuplex = Get-Duplex $cdp
                SwitchIPAddress = Get-SwitchIP $cdp
                VTPMgmtDomain = Get-VTP $cdp
                MACAddress = $dev_info.MACAddress
                IPAddress = $dev_conf.IPAddress
                Domain = $dev_conf.DNSDomain
                Gateway = $dev_conf.DefaultIPGateway
            }
        } else {
            $switch_info =New-Object psobject -Property @{
                ComputerName = $env:COMPUTERNAME
                DeviceID = ("ERROR: {0}" -f $cdp)
                PortID = "ERROR"
                VLAN = "ERROR"
                PortDuplex = "ERROR"
                SwitchIPAddress = "ERROR"
                VTPMgmtDomain = "ERROR"
                MACAddress = "ERROR"
                IPAddress = "ERROR"
                Domain = "ERROR"
                Gateway = "ERROR"
            }
        }
        return $switch_info
    } else {
        $tcpdump_proc.Kill()
        $switch_info =New-Object psobject -Property @{
                ComputerName = $env:COMPUTERNAME
                DeviceID = "ERROR: CDP Packet not detetced!"
                PortID = "ERROR"
                VLAN = "ERROR"
                PortDuplex = "ERROR"
                SwitchIPAddress = "ERROR"
                VTPMgmtDomain = "ERROR"
                MACAddress = $dev_info.MACAddress
                IPAddress = $dev_conf.IPAddress
                Domain = $dev_conf.DNSDomain
                Gateway = $dev_conf.DefaultIPGateway
            }
            return $switch_info
    }
    Remove-Item $tcpdump_stdout
    if ($ShowWarnings) {
        Get-Content $tcpdump_stderr | Write-Warning
    }
    Remove-Item $tcpdump_stderr
}

#if ($PSBoundParameters.ContainsKey('Credential')) {
$creds = (Get-Credential -Message "Use an elevated account (fs or wa):")
#} else {
#    $creds = $null
#}

$i = 0
$computer_waitlist = @()
$computer_results = @()

foreach($computer in $ComputerList) {
    Write-Progress -Activity "Sending CDP/network info query to..." -Status $computer -PercentComplete ($i++/($ComputerList.Count+$computer_waitlist.Count)*100)
    if (Test-ComputerIsOff $computer) {
        if ($RawPacket.IsPresent) {
            $computer_results += "OFFLINE"
        } else {
            $computer_results += New-Object psobject -Property @{
                ComputerName = $computer
                DeviceID = "OFFLINE"
                PortID = "OFFLINE"
                VLAN = "OFFLINE"
                PortDuplex = "OFFLINE"
                SwitchIPAddress = "OFFLINE"
                VTPMgmtDomain = "OFFLINE"
                MACAddress = "OFFLINE"
                IPAddress = "OFFLINE"
                Domain = "OFFLINE"
                Gateway = "OFFLINE"
            }
        }
    } else {
        if ($null -eq $creds) {
            Invoke-Command -ComputerName $computer -ScriptBlock $run_tcpdump -ArgumentList $DeviceNumber,$ShowWarnings.IsPresent,$ShowErrors.IsPresent,$RawPacket.IsPresent -AsJob -JobName $computer
        } else {
            Invoke-Command -ComputerName $computer -ScriptBlock $run_tcpdump -ArgumentList $DeviceNumber,$ShowWarnings.IsPresent,$ShowErrors.IsPresent,$RawPacket.IsPresent -Credential $creds -AsJob -JobName $computer
        }
        $computer_waitlist += $computer
    }
}

foreach ($computer in $computer_waitlist) {
    Write-Progress -Activity "Waiting on..." -Status $computer -PercentComplete ($i++/($computer_list.Count+$computer_waitlist.Count)*100)
    try {
        $job = Receive-Job -Name $computer -Wait -AutoRemoveJob -WriteJobInResults
        if ($job.GetType().Name -eq "PSRemotingJob") { #probably an error
            throw $job.ChildJobs[0].JobStateInfo.Reason
        }
        $computer_results += $job[1]
    } catch {
        if ($RawPacket.IsPresent) {
            $computer_results += ("ERROR: {0}" -f $_.Exception.Message)
        } else {
            $computer_results += New-Object psobject -Property @{
                ComputerName = $env:COMPUTERNAME
                DeviceID = ("ERROR: {0}" -f $_.Exception.Message)
                PortID = "ERROR"
                VLAN = "ERROR"
                PortDuplex = "ERROR"
                SwitchIPAddress = "ERROR"
                VTPMgmtDomain = "ERROR"
                Platform = ""; MACAddress = "ERROR"
                IPAddress = "ERROR"
                Domain = "ERROR"
                Gateway = "ERROR"
            }
        }
    }
}

$computer_results | Export-Csv -NoTypeInformation $OutputCSV
$computer_results | Out-GridView