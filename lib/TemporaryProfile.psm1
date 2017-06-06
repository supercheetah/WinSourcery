function Create-TempUserProfile
{
    $temp_username = "tempuser"
    do {
        $temp_passwd = ([char[]](Get-Random -Input $(48..57 + 65..90 + 97..122) -Count 8)) -join ""
        # Added to ensure that it meets minimum password requirements
        $temp_passwd = ("{0}{1}" -f ($temp_passwd,"Zj3#"))
        #echo "attempting: $temp_passwd"
        & C:\WINDOWS\system32\net.exe user $temp_username $temp_passwd /add | Out-Null 2> $null
        if ($LASTEXITCODE -ne 0) {
            Write-StdErrAndLog "Bad password generated: $temp_passwd"
        }
    } while ($LASTEXITCODE -ne 0)
    $temp_secpasswd = ConvertTo-SecureString $temp_passwd -AsPlainText -Force
    & C:\WINDOWS\system32\net.exe localgroup administrators $temp_username /add | Out-Null
    return New-Object System.Management.Automation.PSCredential ($temp_username, $temp_secpasswd)
}

function Delete-TempUserProfile($temp_credential)
{
    & C:\WINDOWS\system32\net.exe user $temp_credential.UserName /del | Out-Null
    $username = $temp_credential.UserName
    $userdir = "$env:SystemDrive\Users\$username"
    # delete as much as we're able to now, and ignore any errors on what we can't
    # this seems to work better than Remove-Item
    & $env:SystemRoot\system32\cmd.exe /c rd /s /q $userdir | Out-Null 2> $null
    #Remove-Item -Force -Recurse $userdir -ErrorAction SilentlyContinue
    # get a listing of what remains that need to be deleted on reboot
    if (Test-Path $userdir) {
        $dirlist = Get-ChildItem -Path $userdir -Force -Recurse -ErrorAction SilentlyContinue
        $diritems = @()
        foreach ($fullname in $dirlist) {
            $diritems += $fullname.FullName
        }
        # reverse the array so that deletion starts at the leaves of the directory tree
        [array]::Reverse($diritems)
        foreach ($item in $diritems) {
            Write-StdOutAndLog "To be deleted on reboot: $item"
            & "$src_dir\movefile.exe" -accepteula $item '""' | Out-File $log_file -Append
        }
        & "$src_dir\movefile.exe" -accepteula $userdir '""' | Out-File $log_file -Append
    }
}
