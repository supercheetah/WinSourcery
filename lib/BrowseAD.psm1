function Browse-AD([bool]$allow_ou_paste=$false)
{
    # original inspiration: https://itmicah.wordpress.com/2013/10/29/active-directory-ou-picker-in-powershell/
    # author: Rene Horn, rene.horn@convergys.com, the.rhorn@gmail.com
<#
    Copyright (c) 2015, Rene Horn
    All rights reserved.

    Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

    3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#>
    $dc_hash = @{}
    $selected_ou = $null

    Import-Module ActiveDirectory
    $forest = Get-ADForest
    [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null

    function Get-NodeInfo($sender, $dn_textbox)
    {
        $selected_node = $sender.Node
        $dn_textbox.Text = $selected_node.Name
    }

    function Add-ChildNodes($sender)
    {
        $expanded_node = $sender.Node

        if ($expanded_node.Name -eq "root") {
            return
        }

        $expanded_node.Nodes.Clear() | Out-Null

        $dc_hostname = $dc_hash[$($expanded_node.Name -replace '(OU=[^,]+,)*((DC=\w+,?)+)','$2')]
        $child_OUs = Get-ADObject -Server $dc_hostname -Filter 'ObjectClass -eq "organizationalUnit" -or ObjectClass -eq "container"' -SearchScope OneLevel -SearchBase $expanded_node.Name
        if($child_OUs -eq $null) {
            $sender.Cancel = $true
        } else {
            foreach($ou in $child_OUs) {
                $ou_node = New-Object Windows.Forms.TreeNode -Property @{
                    Text = $ou.Name
                    Name = $ou.DistinguishedName
                }
                $ou_node.Nodes.Add('') | Out-Null
                $expanded_node.Nodes.Add($ou_node) | Out-Null
            }
        }
    }

    function Add-ForestNodes($forest, [ref]$dc_hash)
    {
        $ad_root_node = New-Object Windows.Forms.TreeNode -Property @{
            Text = $forest.RootDomain
            Name = "root"
        }
        $ad_root_node.Expand()

        $i = 1
        foreach ($ad_domain in $forest.Domains) {
            Write-Progress -Activity "Querying AD forest for domains and hostnames..." -Status $ad_domain -PercentComplete ($i++ / $forest.Domains.Count * 100)
            $dc = Get-ADDomainController -Server $ad_domain
            $dn = $dc.DefaultPartition
            $dc_hash.Value.Add($dn, $dc.Hostname)
            $dc_node = New-Object Windows.Forms.TreeNode -Property @{
                Name = $dn
                Text = $dc.Domain
            }
            $dc_node.Nodes.Add("") | Out-Null
            $ad_root_node.Nodes.Add($dc_node) | Out-Null
        }

        return $ad_root_node
    }
    
    $main_dlg_box = New-Object System.Windows.Forms.Form -Property @{
        ClientSize = New-Object System.Drawing.Size(400,600)
        MaximizeBox = $false
        MinimizeBox = $false
        FormBorderStyle = 'FixedSingle'
        Text = "Browse Active Directory"
    }

    # widget size and location variables
    $ctrl_width_col = $main_dlg_box.ClientSize.Width/20
    $ctrl_height_row = $main_dlg_box.ClientSize.Height/15
    $max_ctrl_width = $main_dlg_box.ClientSize.Width - $ctrl_width_col*2
    $max_ctrl_height = $main_dlg_box.ClientSize.Height - $ctrl_height_row
    $right_edge_x = $max_ctrl_width
    $left_edge_x = $ctrl_width_col
    $bottom_edge_y = $max_ctrl_height
    $top_edge_y = $ctrl_height_row

    # setup text box showing the distinguished name of the currently selected node
    $dn_text_box = New-Object System.Windows.Forms.TextBox -Property @{
    # can not set the height for a single line text box, that's controlled by the font being used
        Width = (14 * $ctrl_width_col)
        Enabled = $allow_ou_paste
    }
    $dn_text_box.Location = New-Object System.Drawing.Point($left_edge_x, ($bottom_edge_y - $dn_text_box.Height))
    $main_dlg_box.Controls.Add($dn_text_box)
    # /text box for dN

    # setup Ok button
    $ok_button = New-Object System.Windows.Forms.Button -Property @{
        Size = New-Object System.Drawing.Size(($ctrl_width_col * 2), $dn_text_box.Height)
        Text = "Ok"
        DialogResult = 'OK'
    }
    $ok_button.Location = New-Object System.Drawing.Point(($right_edge_x - $ok_button.Width), ($bottom_edge_y - $ok_button.Height))
    $main_dlg_box.Controls.Add($ok_button)
    # /Ok button

    # setup tree selector showing the domains
    $ad_tree_view = New-Object System.Windows.Forms.TreeView -Property @{
        Size = New-Object System.Drawing.Size($max_ctrl_width, ($max_ctrl_height - $dn_text_box.Height - $ctrl_height_row*1.5))
        Location = New-Object System.Drawing.Point($left_edge_x, $top_edge_y)
    }
    $ad_tree_view.Nodes.Add($(Add-ForestNodes $forest ([ref]$dc_hash))) | Out-Null
    $ad_tree_view.Add_BeforeExpand({Add-ChildNodes $_})
    $ad_tree_view.Add_AfterSelect({Get-NodeInfo $_ $dn_text_box})
    $main_dlg_box.Controls.Add($ad_tree_view)
    # /tree selector

    $main_dlg_box.ShowDialog() | Out-Null

    return  $dn_text_box.Text
}