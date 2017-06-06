<#

.SYNOPSIS
Looks for installed applications with a search string to be found in either its
name or the publisher name and uninstalls them.

.DESCRIPTION
It takes a search string (-SearchString) that it uses to look through the names
and publishers for the search string, and uninstalls them.

This was primarily made to be used with SCCM.

.PARAMETER SearchString
Mandatory: Yes

Aliases: p, Publisher

This is the string the script will use to search through the list of applications
in both their names and the publisher name.  This is case insensitive.

.PARAMETER Silent
Mandatory: No

Aliases: s

Suppress progress output, and a dialog box signifying completion.

.EXAMPLE
Uninstall-Universal.ps1 "java" -s

Look for Java to uninstall silently.

.NOTES
At the moment, it only works with packages installed using an MSI installer.  It
has not been tested with other installers, like InstallShield.

Author: Rene Horn, the.rhorn@gmail.com
Version: 0.21
Known issue: this currently only works using msiexec to uninstall things
   - has not been tested with other install programs (e.g. InstallShield)
#>




param (
    [parameter(Mandatory=$true)]
    [alias("p","Publisher")]
    [string]$SearchString,
    [parameter(Mandatory=$false)]
    [alias("File")]
    [string]$ComputerList,
    [parameter(Mandatory = $false)]
    [alias("Exclude","ex","ExcludeGUID")]
    [string[]]$ExcludeList="",
    [parameter(Mandatory=$false)]
    [alias("cn","Name")]
    [string]$ComputerName,
    [parameter(Mandatory=$false)]
    [string]$ResultsFile="results.csv",
    [parameter(Mandatory=$false)]
    [alias("s")]
    [switch]$silent
)

[bool]$silent = $silent.IsPresent

if (!$silent) {
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null
}

$run_uninstaller = {
    param(
        [string]$SearchString,
        [string[]]$ExcludeList
    )

    function Get-ExitCode($process)
    { # different code paths necessary to get the exit code from the process depending on the version of PowerShell being used
        if (4 -le $PSVersionTable.PSVersion.Major) {
            return $process.ExitCode
        } else {
            # work around for bug https://connect.microsoft.com/PowerShell/feedback/details/520554/start-process-does-not-return-exitcode-property
            $process.HasExited|Out-Null
            return $process.GetType().GetField("exitCode","NonPublic,Instance").GetValue($process)
        }
    }

    function Search-Installed([string]$path, [string]$SearchString, [string[]]$ExcludeList)
    { # this is where we look for the search string in the list of installed applications
        #Write-Output "Search string: $SearchString" | Out-File -Append c:\uninst_string.log
        #
        Write-Output "Get-ChildItem -Recurse -ErrorAction SilentlyContinue -Path `"${path}`" | foreach { Get-ItemProperty -Path  $_.PsPath }| Where-Object { ($_.DisplayName -like `"*${SearchString}*`" ) -or ($_.Publisher -like `"*${SearchString}*`") } | Select-Object UninstallString | % { if ( $_ -imatch `"@\{UninstallString=[a-z.]+\s*`/[xi]\s*`{[^}]+`}`}`" ) { ($_ -replace `"@`{[^{]*(`{[^}]+}).*`",'$1') } }" | Out-File -Append c:\uninst_string.log
        #return @(Get-ChildItem -Recurse -ErrorAction SilentlyContinue -Path "${path}" | foreach { Get-ItemProperty -Path  $_.PsPath }| Where-Object { ($_.DisplayName -like "*${SearchString}*" ) -or ($_.Publisher -like "*${SearchString}*") } | Select-Object UninstallString | % { if ( $_ -imatch "@\{UninstallString=[a-z.]+\s*`/[xi]\s*`{[^}]+`}`}" ) { ($_ -replace "@`{[^{]*(`{[^}]+}).*",'$1') } })
        $guid_list = @()
        $guid_list = Get-ChildItem -Recurse -ErrorAction SilentlyContinue -Path "${path}" | foreach { Get-ItemProperty -Path  $_.PsPath } | Where-Object { ($_.DisplayName -like "*${SearchString}*" ) -or ($_.Publisher -like "*${SearchString}*") }
        $curated_guid_list = @()
        foreach ($guid in $guid_list) {
            $include_guid = $true
            foreach ($exguid in $ExcludeList) {
                if ($guid.PSChildName -match $exguid) {
                    $include_guid = $false
                    break
                }
            }
            if ($include_guid) {
                $curated_guid_list += $guid.PSChildName
            }
        }
        
        $guid_list > $null
        return $curated_guid_list
    }


    # setup some local variables
    $uninst_reg = "Microsoft\Windows\CurrentVersion\Uninstall"
    $base_reg_entry = "hklm:\\SOFTWARE"
    $redir_32bit_reg = "Wow6432Node"

    $clsid_list = Search-Installed "${base_reg_entry}\${uninst_reg}" $SearchString $ExcludeList
    $is_64bit = ([IntPtr]::size -eq 8)

    if ($is_64bit) {
        $clsid_list += Search-Installed "${base_reg_entry}\${redir_32bit_reg}\${uninst_reg}" $SearchString $ExcludeList
    }

    $msi_exec = "${env:SystemRoot}\System32\msiexec.exe"
    #$msi_exec = "C:\temp\showarguments.exe"
    $msi_uninst_flag = @("/norestart","/q","/x")
    $msi_log_flag = "/l*v"
    $msi_log = "${env:SystemDrive}\uninstall_${SearchString}.{0}.log"
    $clsid_counter = 1

    # iterate through the list of applications that match our search string, and uninstall them
    foreach ( $clsid in $clsid_list ) {
        $msi_log_current = ($msi_log -f $clsid_counter)
        $msi_args = @($clsid, $msi_log_flag, $msi_log_current)
        $msi_proc = Start-Process -FilePath $msi_exec -ArgumentList @($msi_uninst_flag+$msi_args) -PassThru -Wait
        #Write-Output "Start-Process -FilePath $msi_exec -ArgumentList @($msi_uninst_flag+$msi_args) -PassThru -Wait" | Out-File -Append c:\uninst_string.log
        $msi_exitcode = Get-ExitCode $msi_proc
        $msi_exitcode = 0
        if ($msi_exitcode -ne 0) {
            Write-Error "Error uninstalling, msiexec.exe exit code ${msi_exitcode}, check ${msi_log_current}" 
            Exit $msi_exitcode
        }
        $clsid_counter++
    }
}

function Write-ToProgress($Activity, $Status, [switch]$Completed)
{
    if(!$silent) {
            if ($Completed) {
                Write-Progress -Activity $Activity -Status $Status -Complete
            } else {
                Write-Progress -Activity $Activity -Status $Status
            }
    }
}

function Show-MessageBox($Message, $SearchString)
{
    if(!$silent) {
        [System.Windows.Forms.MessageBox]::Show($Message,"Uninstall of `"$SearchString`" ","Ok","Information","Button1")
    }
}

if (-not [string]::IsNullOrEmpty($ComputerList)) {
    $computer_list = Get-Content $ComputerList
    foreach ($computer in $computer_list) {
        Write-ToProgress -Activity "Uninstalling $SearchString" -Status $computer
        Invoke-Command -ComputerName $computer -ScriptBlock $run_uninstaller -ArgumentList $SearchString,$ExcludeList | Export-Csv -NoTypeInformation $ResultsFile
    }
    Write-ToProgress -Activity "Uninstalling $SearchString" -Status "Completed" -Completed
    Show-MessageBox "Finished..." $SearchString
} elseif (-not [string]::IsNullOrEmpty($ComputerName)) {
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $run_uninstaller -ArgumentList $SearchString,$ExcludeList
} else {
    Write-Error "No computer name or list file provided!"
}
