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
