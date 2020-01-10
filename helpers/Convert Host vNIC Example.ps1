Remove-VMNetworkAdapter -ManagementOS -SwitchName LBFOSwitch
Remove-VMNetworkAdapter -ManagementOS -SwitchName SETSwitch

1..10 | Foreach-Object {
	Add-VMNetworkAdapter -ManagementOS -Name "LBFOHVNIC0$_" -SwitchName LBFOSwitch
}

cls

Get-VMNetworkAdapter -ManagementOS | ?{$_.SwitchName -eq 'LBFOSwitch' -or $_.SwitchName -eq 'SETSwitch'}

Measure-Command {
	1..10 | Foreach-Object {
		C:\temp\LBFOMigration\nvspinfo.exe -r "LBFOHVNIC0$_" SETSwitch
	}
}

Get-VMNetworkAdapter -ManagementOS | ?{$_.SwitchName -eq 'LBFOSwitch' -or $_.SwitchName -eq 'SETSwitch'}
