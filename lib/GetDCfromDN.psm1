function Get-KeyAndValue([string]$line, [string]$delimiter = ":") {
    [string]$key = $null
    [string]$value = $null
    $delim_index = $line.IndexOf($delimiter)
    if ($delim_index -lt 0) { # IndexOf returns -1 if it can't find the delimiter
        return $line, $null
    }
    $key = $line.Substring(0, $delim_index).Trim()
    # have to do it this way so that it captures time stamps properly since they use ":" for delimiters here
    $value = $line.Substring($delim_index + 1, ($line.Length - 1 - $delim_index)).Trim()
    return $key, $value
}

function Get-DCfromDN([string]$dn)
{
    $dc_start = $dn.IndexOf("DC=")
    $domains = $dn.Substring($dc_start, ($dn.Length - $dc_start)).Split(',')
    $string_builder = ""
    foreach($domain in $domains) {
        $key, $val = Get-KeyAndValue $domain '='
        $string_builder += $val + '.'
    }

    return $string_builder.Trim('.')
}
