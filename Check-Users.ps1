<#

.SYNOPSIS

Given a file listing names of users, looks to see if it can find them in AD.

.DESCRIPTION

Check-Users will look through Active Directory (using wildcards for spaces), starting at a 
specified DN for its search base, and return what it's found, including the name it found.

.PARAMETER EmployeeListFile

The path and name of a CSV file with the users to be sought.  The file needs a "Name" column, and optionally Emplid column.

.PARAMETER SearchBase

The DistinguishedName (DN) of the starting point for where to look for the users.

.EXAMPLE

Read the users from a file in the current directory, and output it to OGV.

Check-Users -EmployeeListFile ".\employees.csv" -SearchBase "OU=APP,DC=na,DC=convergys,DC=com"

#>

param(
      [parameter(Mandatory=$true)]
      [alias("ELF")]
      [string]$EmployeeListFile,
      [parameter(Mandatory=$true)]
      [alias("DistringuishedName","DN","SB","OrgUnit","OrganizationalUnit","OU")]
      [string]$SearchBase,
      [parameter(Mandatory=$false)]
      [string]$OutputFile="output.csv"
     )

function Create-Employee-Record([string]$empl_name, [boolean]$ad_found, [boolean]$elf_found, [boolean]$is_common, [string]$ad_cname, [string]$elf_emplid)
{
    [PSCustomObject] @{
        "Name" = $empl_name
        "Found in AD" = $ad_found
        "Found in file" = $elf_found
        "Found in both" = $is_common
        "CanonicalName" = if ($ad_found) { $ad_cname } else { $null }
        "UPN" = if ($ad_found) { $ad_upn } else { $null }
        "Employee ID" = if ($elf_found) { $elf_emplid } else { $null }
    }
}

$employee_list = @(Import-Csv "$EmployeeListFile") | % {[PSCustomObject]@{Name=$_.Name.Trim() -replace '(^[^,]+),\s*(.+)', '$2 $1';Emplid=$_.Emplid}}| Sort-Object -Property Name
$ad_users = Get-ADUser -SearchBase $SearchBase -filter * -Properties Name,GivenName,SurName,CanonicalName | Sort-Object -Property Name

$elf_iter = 0
$ad_iter = 0

$complete_list = @()

function Regexify-String([string]$name)
{
    $name -replace '[\s]',"`\w*`\s*"
}

function Match-Regex([string]$s1, [string]$s2)
{
    if ($s1.Length -le $s2.Length) {
        $re_short_str = Regexify-String $s1
        $long_str = $s2
    } else {
        $re_short_str = Regexify-String $s2
        $long_str = $s1
    }
    $long_str -match $re_short_str
}

function Sanitize-String([string]$name)
{
    $name.Trim() -replace '[^\s\w]',''
}

function Add-ItemUnique($item)
{
    if ($item.PSObject.Properties['CanonicalName']) {
        Create-Employee-Record -empl_name $item.Name -ad_found $true -elf_found $false -is_common $true -ad_cname $item.CanonicalName -elf_emplid $null
    } else {
        Create-Employee-Record -empl_name $item.Name -ad_found $false -elf_found $true -is_common $false -ad_cname $null -elf_emplid $item.Emplid
    }
}

function Add-ItemCommon($less_record, $great_record)
{
    if ($less_record.PSObject.Properties['CanonicalName']) {
        $elf_record = $great_record
        $ad_record = $less_record
    } else {
        $elf_record = $less_record
        $ad_record = $great_record        
    }
    Create-Employee-Record -empl_name $elf_record.Name -ad_found $true -elf_found $true -is_common $true -ad_cname $ad_record.CanonicalName -elf_emplid $elf_record.Emplid
}

function Find-FromLesser([ref]$complete_list, [ref]$less_iter, $great_iter, $less_list, $great_list)
{
    $less_name = Sanitize-String $less_list[$less_iter.Value].Name
    $great_name = Sanitize-String $great_list[$great_iter.Value].Name
    do {    
        $complete_list.Value += Add-ItemUnique $less_list[$less_iter.Value++]
        $less_name = Sanitize-String $less_list[$less_iter.Value].Name
        $great_name = Sanitize-String $great_list[$great_iter.Value].Name
        $re_match = Match-Regex $less_name $great_name
    } while ( ($less_name -lt $great_name) -and ! $re_match )
    if ($re_match) {
        $complete_list.Value += Add-ItemCommon $less_list[$less_iter.Value++] $great_list[$great_iter.Value++]
    }
}

do {
    #$re_elf_name = Regexify-String $employee_list[$elf_iter].Name
    [string]$elf_name = Sanitize-String $employee_list[$elf_iter].Name
    [string]$ad_name = Sanitize-String $ad_users[$ad_iter].Name

    if(Match-Regex $elf_name $ad_name) {
        $complete_list += Add-ItemCommon -less_record $employee_list[$elf_iter++] -great_record $ad_users[$ad_iter++]
    } elseif ($elf_name -lt $ad_name) {
        Find-FromLesser -complete_list ([ref]$complete_list) -less_iter ([ref]$elf_iter) -great_iter ([ref]$ad_iter) -less_list $employee_list -great_list $ad_users
    } else {
        Find-FromLesser -complete_list ([ref]$complete_list) -less_iter ([ref]$ad_iter) -great_iter ([ref]$elf_iter) -less_list $ad_users -great_list $employee_list
    }
} while (($elf_iter -lt $employee_list.Length) -and ($ad_iter -lt $ad_users.Length))

if ($employee_list.Length -gt $ad_users.Length) {
    while ($elf_iter -lt $employee_list.Length) {
        $complete_list += Create-Employee-Record -empl_name $employee_list[$elf_iter].Name -ad_found $false -elf_found $true -is_common $false -ad_cname $null -elf_emplid $employee_list[$elf_iter++].Emplid
    }
} else {
    while ($ad_iter -lt $ad_users.Length) {
        $complete_list += Create-Employee-Record -empl_name $ad_users[$ad_iter].Name -ad_found $true -elf_found $false -is_common $false -ad_cname $ad_users[$ad_iter++].CanonicalName -elf_emplid $null
    }
}

$complete_list | Export-Csv -NoTypeInformation -Path $OutputFile
$complete_list | ogv