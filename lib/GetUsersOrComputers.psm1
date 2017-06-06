#$script_path = Split-Path -Parent $MyInvocation.MyCommand.Definition
Import-Module -Verbose "$PSScriptRoot\BrowseAD.psm1"
Import-Module -Verbose "$PSScriptRoot\GetDCfromDN.psm1"

function Get-ComputerListFromOU
{
    $ou = Browse-AD
    $dc = $(Get-ADDomainController -Server $(Get-DCfromDN $ou)).Hostname
    return $((Get-ADComputer -Server $dc -Filter "*" -SearchBase $ou).DNSHostName)
}

function Get-UserListFromOU
{
    $ou = Browse-AD
    $dc = $(Get-ADDomainController -Server $(Get-DCfromDN $ou)).Hostname
    return $((Get-ADUser -Server $dc -Filter "*" -SearchBase $ou).DNSHostName)
}