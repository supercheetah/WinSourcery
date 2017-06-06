<#
.SYNOPSIS
This script gets MAC address tables from Cisco routers/switches running IOS using the SSH protocol.

.DESCRIPTION
The script uses the Plink (command line version of PuTTY, http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html)
 to get the output of the command "show mac address-table" and put into a object array (i.e. table) that is outputted to
Out-GridView, and can optionally be saved to a CSV file.
#>
# author: Rene Horn, the.rhorn@gmail.com
# requirements:
#   at least PowerShell v3+
#   plink

param(
    [parameter(Mandatory=$false)]
    [alias("CN","Computer","Name","Switch","SwitchName")]
    [string[]]$ComputerName,
    [parameter(Mandatory=$false)]
    [alias("File","Path","List","SwitchListFile")]
    [string]$ComputerListFile,
    [parameter(Mandatory=$false)]
    [string]$SaveFile,
    [parameter(Mandatory=$false)]
    [switch]$NoGUI
)

$DebugPreference = "Continue"

[bool]$NoGUI = $NoGUI.IsPresent

# On some older Cisco IOS hardware (particularly 3750 V1), some wait time between commands is necessary so that we don't get RST packets.
$WAITMSBETWEENCMDS = 1050

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Error "PowerShell 3.0 or higher is required!"
    Exit -1
}

function Get-PlinkPath()
{
    if(!($plink_exe = Get-Command plink.exe -ErrorAction SilentlyContinue)) {
        Write-Error "plink.exe not found! Download that first and put it in the path: https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html"
        Exit 1
    } else {
        return $plink_exe.Path
    }
}

function Construct-ObjectFromHeader([string]$computer,[string[]]$headers,[string[]]$split_line)
{
    [pscustomobject]$tbl_object = New-Object psobject -Property @{"hostname"=$computer}
    for($i=0; $i -lt $headers.Count; $i++) {
        $tbl_object | Add-Member -MemberType NoteProperty -Name $headers[$i] -Value $split_line[$i]
    }
    # ugly side-effect hack, strip the [.] here instead of later in the code
    $tbl_object.'Mac Address' = $tbl_object.'Mac Address' -replace '[.]',''
    return $tbl_object
}

function Match-CiscoIOSPrompt([string]$line)
{
    return $line -match "^\S+>.*"
}

function Parse-Output([string]$computer, [string[]]$output_raw, [string[]]$cmds)
{
    $output_iter = 0
    for (; $output_iter -lt $output_raw.Count; $output_iter++) {
        if (Match-CiscoIOSPrompt $output_raw[$output_iter]) {
            break
        }
    }

    for(; $output_iter -lt $output_raw.Count; $output_iter++) {
        if ((-not (Match-CiscoIOSPrompt $output_raw[$output_iter])) -and (-not ([string]::IsNullOrEmpty($output_raw[$output_iter])))) {
            $output_iter++
            break
        }
    }

    $cmds_results_hash = @{}
    $line_split_re = "\s{2}\s*"
    foreach($cmd in $cmds) {
        # we don't care about the first two lines of the output...
        # this regex split allows us to capture headers like "Mac Address"
        # TODO: a more complex table parser would be needed for other tables, e.g. for "show interface status"
        $headers = [regex]::Split($output_raw[$output_iter++].Trim(), $line_split_re)
        $output_tbl = @()
        do {
            $output_tbl += Construct-ObjectFromHeader $computer $headers ([regex]::Split($output_raw[$output_iter].Trim(), $line_split_re))
            #$output_tbl[$output_iter].'Mac Address' = $output_tbl[$output_iter].'Mac Address' -replace '[.]',''
        } while ((-not (Match-CiscoIOSPrompt $output_raw[++$output_iter])) -and ($output_iter -lt $output_raw.Count))
        $cmds_results_hash[$cmd] = $output_tbl
        $output_iter+=1 # skip blank line after command
        if ($output_iter -ge $output_raw.Count) {
            Write-Error "Truncated output!"
            break
        }
    }
    return $cmds_results_hash
}

function Ask-ForHostKeyAccept([string]$host_key_err_msg)
{
    $split_string = $host_key_err_msg.Trim().Split("`n")
    [string[]]$relevant_strings = @()
    foreach ($s in $split_string) {
        if (($relevant_strings.Count -gt 0) -or ($s -match "^The server's host key is not cached in the registry.*")) {
            $relevant_strings += $s
        }

        if ($s -match "^ssh-.*") { break }
    }
    $caption = "Accept host key?"
    $message = (@"
{0}
If you trust this host, click Yes to add the key to
PuTTY's cache and carry on connecting.
If you want to carry on connecting just once, without
adding the key to the cache, click No.
If you do not trust this host, click Cancel to abandon the
connection.
Store key in cache?
"@ -f [string]::Join("`n", $relevant_strings))

    $response = [System.Windows.Forms.MessageBox]::Show($message, $caption, "YesNoCancel", "Warning", "Button1", 0)
    if ($response -eq "Yes") {
        return 'y'
    } elseif ($response -eq "No") {
        return 'n'
    } else {
        return "`n"
    }
}

function WaitFor-ThreadUserRequest([System.Diagnostics.Process]$proc, [int]$max_wait_ms=3000)
{
    $keep_waiting = $true
    Write-Debug "Waiting for user input..."
    Write-Debug (Get-PSCallStack | Out-String)
    Write-Debug ($proc.Threads | Out-String)
    $total_proc_time_prev = $proc.TotalProcessorTime
    $dont_spam = 0
    $tpt_no_change_count = 0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($keep_waiting -and ($timer.ElapsedMilliseconds -lt $max_wait_ms)) {
        if ($proc.HasExited) { break }
        if ($dont_spam++ -eq 10) {
            Write-Debug ($proc.Threads | Out-String)
            $dont_spam = 0
        }

        foreach ($thread in $proc.Threads) {
            if (($thread.ThreadState -eq "Wait") -and (($thread.WaitReason -eq "UserRequest") -or ($thread.WaitReason -eq "LpcReply")) -or ($thread.ThreadState -eq "Running") -or ($thread.ThreadState -eq "Ready")) {
            #if ($thread.ThreadState -eq "Wait") {
                $keep_waiting = $false
                break
            }
        }
    }
}

function Write-ErrorFile([string]$computer, [string]$plink_stderr, [string]$plink_stdout, [int]$err_code)
{
    $plink_err_file = "$pwd\$computer.error.log"
    Write-Output "plink returned with an error code of $err_code" | Out-File $plink_err_file
    $plink_stderr | Out-File -Append $plink_err_file
    $plink_stdout_file = "$pwd\$computer.stdout.log"
    $plink_stdout | Out-File $plink_stdout_file
    Write-Error "Connection to $computer failed, check $plink_err_file and $plink_stdout_file."
}

function Test-HostKeyIsCached([string]$plink_stderr_result)
{
    $err_split = $plink_stderr_result.Trim().Split("`n")
    [string[]]::Reverse($err_split)
    foreach ($err_line in $err_split) {
        if ($err_line.Trim() -match "Connection abandoned.") {
            return $false
        }
    }
    return $true
}

function Set-PlinkInfo([string]$computer, [pscredential]$credentials, $batch=$true)
{
    # returns: System.Diagnostics.Process for plink, StreamReader for its stdin, stdout, and async read variables for stdout and stderr, respectively
    # if this returns null, that means the host key was rejected
    $plink_exe = Get-PlinkPath

    $plink_proc_info = New-Object System.Diagnostics.ProcessStartInfo
    $plink_proc_info.FileName = $plink_exe
    $plink_proc_info.UseShellExecute = $false
    $plink_proc_info.RedirectStandardError = $true
    $plink_proc_info.RedirectStandardInput = $true
    $plink_proc_info.RedirectStandardOutput = $true
    $plink_proc_info.CreateNoWindow = $true
    # putting the arguments here to minimize the amount of time the password shows up in clear text in memory
    $plink_proc_info.Arguments = ('-v','-2',('-pw {0} {1}@{2}' -f $credentials.GetNetworkCredential().Password, $credentials.GetNetworkCredential().UserName, $computer))
    if ($batch) {
        $plink_proc_info.Arguments = '-batch ' + $plink_proc_info.Arguments
    }
    
    return $plink_proc_info
}

function New-PlinkSession([string]$computer, [string[]]$cisco_ios_cmds, [pscredential]$credentials)
{
    # The process start info needs to be set up separately.
    # Creating a new System.Diagnostics.Process object, and setting up its StartInfo, and then starting it doesn't seem to work.
    # Also, calling plink directly here does not work properly, nor does using Start-Process.  The output always gets truncated if there's too much.
    # The reason seems to be that .NET has a buffer limit (http://www.codeducky.org/process-handling-net/) for stdin, stdout, and stderr, so they
    # need to be written to/read from asynchronously so that those streams will have some other buffer to use that don't have those limitations.
    $plink_proc_info = Set-PlinkInfo $computer $credentials
    
    $plink_proc = [System.Diagnostics.Process]::Start($plink_proc_info)
    Write-Debug "plink started..."
    WaitFor-ThreadUserRequest $plink_proc

    if ($plink_proc.HasExited) {
        $plink_stderr = $plink_proc.StandardError.ReadToEndAsync().Result
        
        if (Test-HostKeyIsCached $plink_stderr) {
            Write-ErrorFile $computer $plink_stderr $plink_proc.StandardOutput.ReadToEndAsync().Result $plink_proc.ExitCode
            return $null
        }

        $host_key_accepted = (Ask-ForHostKeyAccept $plink_stderr)
        if ($host_key_accepted -eq "`n") {
            Write-Warning "Host key not accepted, skipping $computer..."
            return $null
        }
        Write-Debug "Sending host key acceptance to plink..."
        $plink_proc_info = Set-PlinkInfo $computer $credentials $false
        $plink_proc = [System.Diagnostics.Process]::Start($plink_proc_info)
        WaitFor-ThreadUserRequest $plink_proc
        $plink_proc.StandardInput.WriteLine("$host_key_accepted")
    }
    $plink_proc_info.Arguments = "" # for security reasons, blanking this out so there aren't so many copies of the password in clear text floating around in memory
    return $plink_proc, [System.IO.StreamWriter]($plink_proc.StandardInput), $plink_proc.StandardOutput.ReadToEndAsync(), $plink_proc.StandardError.ReadToEndAsync()
}

function Get-ServerExitStatus([string]$stderr, [int]$proc_exitcode)
{
    $split_lines = $stderr.Trim().Split("`n")
    $srv_exit_line_re = "^Server sent command exit status (\d+)"
    for ($i = $split_lines.Count; $i -ge 0; $i--) {
        Write-Debug ("line {0}: {1}" -f $i, $split_lines[$i])
        if ($split_lines[$i] -match $srv_exit_line_re) {
            Write-Debug "`tMatches"
            [int]$exit = $split_lines[$i] -replace $srv_exit_line_re,'$1'
            return $exit
        }
    }

    return $proc_exitcode
}

function Invoke-CiscoIOSCmds([string]$computer, [string[]]$cisco_ios_cmds, [pscredential]$credentials)
{
    $wait_multiplier = 1
    # PowerShell seems to lock stdin and stdout until the process exits, so we can't do anything with them until it exits.
    $plink_proc, $plink_stdin, $plink_stdout, $plink_stderr = New-PlinkSession $computer $cisco_ios_cmds $credentials $host_key_results_err
    if ($plink_proc -eq $null) {
        return $null
    }
    # We don't want to use WriteLine() here because it writes \n\r to the stream, which gets interpreted as two EOLs by Cisco IOS
    $plink_stdin.Write("terminal length 0`n")
    # Cisco IOS gets a little weird if it doesn't get a break between commands, so we sleep for a bit.
    WaitFor-ThreadUserRequest $plink_proc
    foreach ($cmd in $cisco_ios_cmds) {
        $plink_stdin.Write("$cmd`n")
        WaitFor-ThreadUserRequest $plink_proc
    }

    $plink_stdin.Write("exit`n")
    $plink_proc.WaitForExit()
    
    if ($plink_proc.ExitCode -ne 0) {
        # Check stderr for the actual exit status from the server
        if ((Get-ServerExitStatus $plink_stderr.Result $plink_proc.ExitCode) -ne 0) {
            Write-ErrorFile $computer $plink_stderr.Result $plink_stdout.Result $plink_proc.ExitCode
            return $null
        } # Disregard plink's exit code because it's wrong...
    }
    [string]$stdout_buf = $plink_stdout.Result # Seems to be necessary otherwise the split op below has some weird behavior
    $cmds_output = Parse-Output $computer $stdout_buf.Split("`n") $cisco_ios_cmds
    return $cmds_output
}

function Get-AddressTables([string[]]$computer_list) {
    begin {
        $credentials = (Get-Credential)
        if ($credentials -eq $null) {
            Write-Error "Logon cancelled, abandon all hope..."
            Exit -15
        }
        $cisco_ios_cmd = "sh mac address-table | e -|CPU|Mac Address Table|Total"
    }
    process {
        $address_table = @()
        $i = 1
        foreach ($computer in $computer_list) {
            Write-Progress -Activity "Getting MAC address table..." -Status $computer -PercentComplete ($i++/$computer_list.Count*100.00)
            $buffer = Invoke-CiscoIOSCmds $computer.Trim() $cisco_ios_cmd $credentials
            if ($buffer -ne $null) {
                $address_table += $buffer[$cisco_ios_cmd]
            }
        }
        return $address_table
    }
    end {}
}

function Open-ComputerListFile()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $open_file_dlg = New-Object System.Windows.Forms.OpenFileDialog
    $open_file_dlg.Filter = "All files (*.*)| *.*"
    $open_file_dlg.ShowDialog() | Out-Null
    $open_file_dlg.FileName
}

function Save-ReportFile()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

    $save_file_dlg = New-Object System.Windows.Forms.SaveFileDialog
    $save_file_dlg.Filter = "CSV file (*.csv) | *.csv"
    $save_file_dlg.OverwritePrompt = $true
    $save_file_dlg.ShowDialog() | Out-Null
    $save_file_dlg.FileName
}

function Show-GUI()
{
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

    # creating it here so we can get the default height of a single line text box for reference
    $computer_list_textbox = New-Object System.Windows.Forms.TextBox
    $textbox_height = $computer_list_textbox.Height

    $main_dlg_box = New-Object System.Windows.Forms.Form -Property @{
        ClientSize = New-Object System.Drawing.Size(600,($textbox_height*16))
        MaximizeBox = $false
        MinimizeBox = $false
        FormBorderStyle = 'FixedSingle'
        Text = "Get MAC address tables"
    }

    # widget size and location variables
    $ctrl_width_col = $main_dlg_box.ClientSize.Width/15
    $ctrl_height_row = $textbox_height
    $max_ctrl_width = $main_dlg_box.ClientSize.Width - $ctrl_width_col*2
    $max_ctrl_height = $main_dlg_box.ClientSize.Height - $ctrl_height_row*2
    $right_edge_x = $max_ctrl_width
    $left_edge_x = $ctrl_width_col
    $bottom_edge_y = $max_ctrl_height
    $top_edge_y = $ctrl_height_row

    $computer_list_label = New-Object System.Windows.Forms.Label -Property @{
        Size = New-Object System.Drawing.Size($max_ctrl_width, $textbox_height)
        Text = "Enter Cisco switch/router hostnames/IP addresses (comma separated or each on their own line):"
        Location = New-Object System.Drawing.Point($left_edge_x, $top_edge_y)
    }
    $main_dlg_box.Controls.Add($computer_list_label)

    $computer_list_textbox.Multiline = $true
    $computer_list_textbox.Height = $textbox_height*6
    $computer_list_textbox.Width = $max_ctrl_width
    $computer_list_textbox.Location = New-Object System.Drawing.Point($left_edge_x, ($top_edge_y + $ctrl_height_row))
    $main_dlg_box.Controls.Add($computer_list_textbox)

    $open_listfile_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*4), $textbox_height)
        Location = New-Object System.Drawing.Point($left_edge_x, ($computer_list_textbox.Height + $computer_list_textbox.Location.Y + $ctrl_height_row))
        Text = "&Open file with hostnames"
    }
    $open_listfile_button.Add_Click({$main_dlg_box.Enabled=$false; $open_listfile_textbox.Text=Open-ComputerListFile; $main_dlg_box.Enabled=$true})
    $main_dlg_box.Controls.Add($open_listfile_button)

    $open_listfile_textbox = New-Object System.Windows.Forms.TextBox -Property @{
        Size = New-Object System.Drawing.Size(($max_ctrl_width - $open_listfile_button.Width - $ctrl_width_col*2), $textbox_height)
        ReadOnly = $true
        BackColor = $main_dlg_box.BackColor
        TabStop = $false
    }
    $open_listfile_textbox.Location = New-Object System.Drawing.Point(($right_edge_x - $open_listfile_textbox.Width), $open_listfile_button.Location.Y)
    $main_dlg_box.Controls.Add($open_listfile_textbox)

    $save_file_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size($open_listfile_button.Width, $textbox_height)
        Location = New-Object System.Drawing.Point($left_edge_x, ($open_listfile_button.Height + $open_listfile_button.Location.Y + $ctrl_height_row))
        Text = "&Save report to..."
    }
    $save_file_button.Add_Click({$main_dlg_box.Enabled=$false; $save_file_textbox.Text=Save-ReportFile; $main_dlg_box.Enabled=$true})
    $main_dlg_box.Controls.Add($save_file_button)

    $save_file_textbox = New-Object System.Windows.Forms.TextBox -Property @{
        Size = New-Object System.Drawing.Size(($max_ctrl_width - $save_file_button.Width - $ctrl_width_col*2), $textbox_height)
        ReadOnly = $true
        BackColor = $main_dlg_box.BackColor
        TabStop = $false
    }
    $save_file_textbox.Location = New-Object System.Drawing.Point(($right_edge_x - $save_file_textbox.Width), $save_file_button.Location.Y)
    $main_dlg_box.Controls.Add($save_file_textbox)

    $ok_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*2), $textbox_height)
        DialogResult = "OK"
        Text = "O&k"
    }
    $ok_button.Location = New-Object System.Drawing.Point(($right_edge_x - $ok_button.Width), ($bottom_edge_y - $ok_button.Height))
    $main_dlg_box.Controls.Add($ok_button)

    $cancel_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col*2), $textbox_height)
        DialogResult = "Cancel"
        Text = "&Cancel"
    }
    $cancel_button.Location = New-Object System.Drawing.Point($left_edge_x, $ok_button.Location.Y)
    $main_dlg_box.Controls.Add($cancel_button)

    if($main_dlg_box.ShowDialog() -eq "Cancel") {
        return $null
    } else {
        return ([regex]::Split($computer_list_textbox.Text.Trim(), ",|`n")), $open_listfile_textbox.Text, $save_file_textbox.Text
    }
}

$computer_list = $null
while([string]::IsNullOrEmpty($computer_list)) {
    if (![string]::IsNullOrEmpty($ComputerName)) {
        $computer_list = @($ComputerName)
    } elseif (![string]::IsNullOrEmpty($ComputerListFile)) {
        $computer_list = (Get-Content -Path $ComputerListFile)
    } elseif($NoGUI) {
        $buffer = Read-Host "Please specify a switch/rouer hostname(s) (comma separated) or file containing the hostnames"
        if (Test-Path $buffer -ErrorAction SilentlyContinue) {
            $ComputerListFile = $buffer
        } elseif ($buffer -match "(\w+,?)+") { # if it's not a valid file path, assume we were given a hostname(s)
            $ComputerName = $buffer.Split(",")
        } else {
            Write-Error "I don't understand!"
        }
    } else {
        $buffer = Show-GUI
        if ($buffer -ne $null) {
            $ComputerName, $ComputerListFile, $SaveFile = $buffer
        } else {
            Exit 0
        }
    }
}
$address_tables = Get-AddressTables $computer_list

if (![string]::IsNullOrEmpty($SaveFile)) {
    $address_tables | Export-Csv -Path $SaveFile -NoTypeInformation
}

$address_tables | ogv -Wait -Title "MAC address tables"
