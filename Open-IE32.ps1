<#
.SYNOPSIS
Boilerplate code for opening IE in 32 bit mode.

.DESCRIPTION
Use this in a new script for when it's needed to make sure that Internet Explorer opens in 32 bit mode.
#>

param(
    [parameter(Mandatory=$false)]
    [string]$URL
)

function Add-ToCompatView($domains)
{ # inspired by http://jeffgraves.me/2014/02/19/modifying-ie-compatibility-view-settings-with-powershell/
    $key = "HKCU:\Software\Microsoft\Internet Explorer\BrowserEmulation\ClearableListData"
    $item = "UserFilter"

    [byte[]] $regbinary = @()

    #This seems constant
    [byte[]] $header = 0x41,0x1F,0x00,0x00,0x53,0x08,0xAD,0xBA

    #This appears to be some internal value delimeter
    [byte[]] $delim_a = 0x01,0x00,0x00,0x00

    #This appears to separate entries
    [byte[]] $delim_b = 0x0C,0x00,0x00,0x00

    #This is some sort of checksum, but this value seems to work
    [byte[]] $checksum = 0xFF,0xFF,0xFF,0xFF

    #This could be some sort of timestamp for each entry ending with 0x01, but setting to this value seems to work
    [byte[]] $filler = 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x01

    function Get-DomainEntry($domain) 
    {
        [byte[]] $tmpbinary = @()

        [byte[]] $length = [BitConverter]::GetBytes([int16]$domain.Length)
        [byte[]] $data = [System.Text.Encoding]::Unicode.GetBytes($domain)

        $tmpbinary += $delim_b
        $tmpbinary += $filler
        $tmpbinary += $delim_a
        $tmpbinary += $length
        $tmpbinary += $data

        return $tmpbinary
    }

    [byte[]] $entries = @()

    [int32] $count = $domains.Length
    foreach($domain in $domains) {
        $entries += Get-DomainEntry $domain
    }
    
    $regbinary = $header
    $regbinary += [byte[]] [BitConverter]::GetBytes($count)
    $regbinary += $checksum
    $regbinary += $delim_a
    $regbinary += [byte[]] [BitConverter]::GetBytes($count)
    $regbinary += $entries

    if (-not (Set-ItemProperty -Path $key -Name $item -Value $regbinary -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path $key)) {
            New-Item -Path $key | Out-Null
        }
        if (-not (Get-ItemProperty -Path $key | Select-Object -ExpandProperty $item -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $key -Name $item -Value $regbinary | Out-Null
        }
    }
}

[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

if ([System.Windows.Forms.MessageBox]::Show("Close all Internet Explorer windows?", "Close IE Windows", 4) -eq "YES") {
    Stop-Process -Name "iexplore*" -Force
}

Add-ToCompatView @("convergys.com")

Remove-ItemProperty "HKCU:\Software\Microsoft\Internet Explorer\Main" TabProcGrowth -ErrorAction SilentlyContinue
& "C:\Program Files (x86)\Internet Explorer\iexplore.exe" "$URL"

Exit