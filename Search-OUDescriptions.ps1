<#
.SYNOPSIS
Search through AD for a term.

.DESCRIPTION
Given a term, SearchTerm as a parameter, this will look through an Active Directory forest for all the descriptions that contain that term.
#>

param(
    [parameter(Mandatory=$true)]
    [string[]]$SearchTerms,
    [parameter(Mandatory=$false)]
    [ValidateSet('Base','OneLevel','Subtree')]
    [string]$SearchScope='OneLevel',
    [parameter(Mandatory=$false)]
    [string]$OutputCSV="searchoudescriptions.csv"
)

$forest = Get-ADForest

$ou = @()
foreach ($SearchTerm in $SearchTerms) {
    foreach ($domain in $forest.Domains) {
        $ou += Get-ADOrganizationalUnit -LDAPFilter "(description=*$SearchTerm*)" -Server $domain -SearchScope $SearchScope -Properties Description
    }
}

$ou | Export-Csv -NoTypeInformation $OutputCSV
$ou | ogv