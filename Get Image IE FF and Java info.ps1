<#
.SYNOPSIS
Looks for the versions of IE, Firefox, and Java on computers in a particular OU.

.DESCRIPTION
Looks in the C drive of computers for the versions of Internet Explorer, Firefox, and all versions of Java that it can find.
It will ask for the OU to look into from an AD forest if none is provided.
#>
Param(
    [parameter(Mandatory=$false)]
    [alias("OrganizationalUnit","DistinguishedName","DN","SearchBase","SB")]
    [string]$OU,
    [parameter(Mandatory=$false)]
    [alias("File")]
    [string]$OutputFile="output.csv",
    [parameter(Mandatory=$false)]
    [alias("Offline")]
    [string]$OfflineFile="offline.csv"
)

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$script_path\lib\TestComputerIsOff.psm1"
Import-Module -Verbose "$script_path\lib\GetUsersOrComputers.psm1"

$Computers = @()
if ([string]::IsNullOrEmpty($OU)) {
    $Computers = Get-ComputerListFromOU
}

$colOutput = @()
$offlineComputers = @()

$applications = @{
# if there are apps that you don't need to check, just comment them out here
# add more lines for other apps not already listed
                  "Internet Explorer" = @("Program Files\Internet Explorer\iexplore.exe")
                  ;"Mozilla Firefox"   = @("Program Files (x86)\Mozilla Firefox\firefox.exe",
                                        "Program Files\Mozilla Firefox\firefox.exe")
                  ;"Chrome Frame"      = @("Program Files (x86)\Google\Chrome Frame\Application\chrome.exe")
                  ;"SDCS"              = @("Program Files (x86)\Symantec\Data Center Security Server\Agent\IPS\bin\sisipsconfig.exe")
                 }
                  
Function Get-NameValue($ContentInput, $Filter, $offset = 2, $delimeter = ':')
{
    $buffer = $ContentInput | Where { $_ -like $Filter }
    $buffer = $buffer.Substring($buffer.IndexOf($delimeter) + $offset)
    $buffer
}

Function Get-AppVersions($ComputerName, $objOutput)
{
    foreach ($app in $applications.GetEnumerator() ) {
        $versions = @()
        foreach ($location in $app.value) {
            if ( ! (Test-Path "\\$ComputerName\c$\$location") ) {
                Write-Warning "$location does not exist on $ComputerName, skipping..."
                $versions += "N/A"
                Continue
            }
            $versions += (Get-Item "\\$ComputerName\c$\$location").VersionInfo.FileVersion
        }
        $objOutput | Add-Member -Type NoteProperty -Name $app.key -Value ($versions -join ',').Trim(',')
    }
}

Function Get-JavaVersions($ComputerName, $objOutput)
{ # accommadating that there could be multiple Java versions, and that the version info isn't in java.exe
    $javaLocations = @("Program Files (x86)\Java",
                       "Program Files\Java")
    $versions = @()
    foreach($location in $javaLocations) {
        if ( ! (Test-Path "\\$ComputerName\c$\$location") ) {
            Write-Warning "$location does not exist on $ComputerName, skipping..."
            $versions += "N/A"
            Continue
        }
        $javaFiles = (Get-ChildItem -Recurse -Path "\\$ComputerName\c$\$location" -Include "java.exe").PSPath | Convert-Path
        foreach($jFile in $javaFiles) {
            $version = (Get-Item $jFile).VersionInfo.ProductVersion
            if ($null -eq $version) {
               $version = Split-Path -Leaf (Split-Path (Split-Path $jFile))
            }
            $versions += $version
        }
    }
    $objOutput | Add-Member -Type NoteProperty -Name "Java Versions" -Value ($versions -join ',').Trim(',')
}

ForEach($Computer in $Computers) {
    if( Test-ComputerIsOff($Computer) ) {
        Write-Host "Adding $Computer to offline list"
        $offlineComputers += $Computer
        continue
    }
    Write-Host "Checking image on $Computer"

    $ImageFile = Get-Content "\\$Computer\c$\windows\SCCMImageInfo.txt"

    $objOutput = New-Object System.Object
    $objOutput | Add-Member -type NoteProperty -name Computer -value $Computer
    $ImageName = Get-NameValue $ImageFile "*Image Name*"
    $objOutput | Add-Member -type NoteProperty -name ImageName -value ($ImageName)
    $ImageLOB = Get-NameValue $ImageFile "*LOB*"
    $objOutput |Add-Member -type NoteProperty -name ImageLOB -Value ($ImageLOB)
    $ImageDate = Get-NameValue $ImageFile "*Imaging Date*" 12
    $ImageDate = $ImageDate.Replace('at ', '')
    $ImageDate = [DateTime]$ImageDate
    $objOutput | Add-Member -type NoteProperty -name ImageDate -value ($ImageDate)
    Get-AppVersions $Computer $objOutput
    Get-JavaVersions $Computer $objOutput

    $colOutput += $objOutput
}

$colOutput | Export-Csv -NoTypeInformation $OutputFile
$offlineComputers > $OfflineFile

$colOutput | ogv