Function Test-ComputerIsOff
{
    param(
        [Parameter(Mandatory = $true)]
        $ComputerName
    )

    # Write-Host "Pinging $ComputerName"

    & C:\WINDOWS\system32\PING.EXE -n 1 -w 1000 $ComputerName | Out-Null
    return $LASTEXITCODE -ne 0
}
