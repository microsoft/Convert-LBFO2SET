Remove-VMSwitch    -Name SETTeam    -ErrorAction SilentlyContinue
Remove-VMSwitch    -Name LBFOSwitch -Force -ErrorAction SilentlyContinue
Remove-NetLbfoTeam -Name LBFOTeam   -Confirm:$false -ErrorAction SilentlyContinue

New-NetLbfoTeam -Name LBFOTeam   -TeamMembers 'Ethernet 4','Ethernet 5' -Confirm:$false | Out-Null
New-VMSwitch    -Name LBFOSwitch -AllowManagementOS $false -NetAdapterName LBFOTeam -ErrorAction SilentlyContinue | Out-Null
#New-VMSwitch    -Name SETTeam -EnableEmbeddedTeaming $true -AllowManagementOS $false -NetAdapterName 'Ethernet' -ErrorAction SilentlyContinue

Connect-VMNetworkAdapter -VMNetworkAdapterName 'Network Adapter' -SwitchName LBFOSwitch -VMName 'LBFO VM 01', 'LBFO VM 02'

Add-VMNetworkAdapter -ManagementOS -SwitchName LBFOSwitch -Name LBFOTest01 | Out-Null
Add-VMNetworkAdapter -ManagementOS -SwitchName LBFOSwitch -Name LBFOTest02 | Out-Null
Add-VMNetworkAdapter -ManagementOS -SwitchName LBFOSwitch -Name LBFOTest03 | Out-Null

Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName 'LBFOTest01' -VlanId 102 -Access
Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName 'LBFOTest02' -Trunk -NativeVlanId 8 -AllowedVlanIdList 9
Set-VMNetworkAdapterIsolation -ManagementOS -VMNetworkAdapterName 'LBFOTest03' -IsolationMode Vlan -DefaultIsolationID 101

Convert-LBFO2Set -LBFOTeam LBFOTeam -SETTeam SETTeam -AllowOutage -EnableBestPractices