Function get-freespace($server)
{
$Disks = gwmi -computername $Server win32_logicaldisk -filter "drivetype=3"
foreach ($Disk in $Disks|?{$_.deviceid -eq "C:"}){$freeGB=[math]::round($Disk.FreeSpace/1GB,2)}
if(![bool]$freeGB){$freeGB=0}
return $freeGB
}
Function get-pendingreboot($server)
{
$HKLM = 2147483650
$pending="0i"
$reg = gwmi -List -Namespace root\default -ComputerName $server | Where-Object {$_.Name -eq "StdRegProv"}
	if($reg.Enumkey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update").snames -contains "RebootRequired"){$pending="1i"}
	elseif($reg.Enumkey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing").snames -contains "RebootPending"){$pending="1i"}
	elseif($reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\Session Manager","PendingFileRenameOperations").sValue){$pending="1i"}
	elseif($reg.GetStringValue($HKLM,"SOFTWARE\Wow6432Node\Sophos\AutoUpdate\UpdateStatus\VolatileFlags","RebootRequired").sValue){$pending="1i"}
return $pending
}
Function get-sophoserr($server)
{
$err="0i"
try{
	$sophosfile=(gci "\\$server\C$\ProgramData\Sophos\AutoUpdate\Logs\ALUpdate*.log"|sort lastwritetime -desc|select fullname -first 1).fullname
	$filecontent=get-content($sophosfile)|select -last 15
		foreach($line in $filecontent|sort -desc)
		{
		#$line
			if($line -match 'Sending message:')
			{
			if ($line -match "Install.Failure"){$err="1i"}
			break
			}
		}
		#write-host $err -fore magenta
	}
catch{$err="2i"}
return $err
}#fin sophoserr

#cargo el snappin de CITRIX
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#cargo el snapin de Citrix 7
asnp citrix*
#cargo las funciones de influxdb
import-module "$PSscriptroot\..\..\InfluxDB-Powershell-Module"

#CITRIX LICENSES
$citrixlicenses=get-brokersite|select -expand licensedsessionsactive
$body="citrix7licenses,farm=XenApp7 licensesinuse=$citrixlicenses,totallicenses=540"
$body
write-influxDB "monitoringdb" $body
#CITRIX SERVERS STATUS
$templatewks=import-csv "$scriptPath\XAmaintenance_template.csv" -delimiter "`t"
$XAsessions=get-brokersession -protocol HDX|select MachineName,sessionstate,appstate,protocol,SessionType,applicationsinuse,BrokeringUserName,ClientVersion,ConnectionMode,Clientaddress
$XAServers=get-brokerdesktop|select CatalogName,DesktopGroupName,AssociatedUserUPNs,AgentVersion,InMaintenanceMode,LastConnectionFailure,LastDeregistrationTime,MachineInternalState,MachineName,Tags
$XAServers|%{
	$objserver=""|select servername,load,missingwk,maintenance,activesessions,inactivesessions,pendingreboot,sophoserr
	$machinename=$_.machinename
	$objserver.servername=$machinename.split('\')[1]
	$objserver.activesessions=($XAsessions|?{$_.machinename -eq $machinename -and $_.sessionstate -eq "Active"}|measure-object).count
	$objserver.inactivesessions=($XAsessions|?{$_.machinename -eq $machinename -and $_.sessionstate -eq "Disconnected"}|measure-object).count
	$objserver.pendingreboot=get-pendingreboot $objserver.servername
	$objserver.sophoserr=get-sophoserr $objserver.servername
	$freeGB=get-freespace $objserver.servername

	$servkerwks=$templatewks|?{$_.servername -eq $objserver.servername}|select -expand tag
	$maintenance=compare-object -referenceObject $servkerwks -DifferenceObject ($_|select -expand tags)|?{$_.sideindicator -eq "<="}|select -expand inputobject
		if ([bool]$maintenance)
		{
		if ($maintenance.count -eq $servkerwks.count){$objserver.maintenance="2i"}
		else{$objserver.maintenance="1i"}
		$objserver.missingwk=$maintenance -join ";"
		}
		else
		{
		$objserver.missingwk="-"
		$objserver.maintenance="0i"		
		}
		if($_.InMaintenanceMode){$objserver.maintenance="3i"}
	$body="citrix7servers,farm=XenApp7,servername=$($objserver.servername),missingwk=$($objserver.missingwk) activesessions=$($objserver.activesessions),inactivesessions=$($objserver.inactivesessions),maintenance=$($objserver.maintenance),pendingreboot=$($objserver.pendingreboot),sophoserr=$($objserver.sophoserr),free=$freeGB"
	$body
	write-influxDB "monitoringdb" $body
	}
#CITRIX CLIENT VERSIONS
$xasessions|?{$_.clientversion}|select @{l='ver';e={$_.clientversion.split(".")[0]}}|group ver|%{
	$body="citrix7versions,farm=XenApp7,version=$($_.name) count=$($_.count)i"
	$body
	write-influxDB "monitoringdb" $body
	}
#CITRIX CLIENT SUBNETS
$subnets=@{'vpn'=0;'lan'=0;'wan'=0}
$xasessions|?{$_.Clientaddress}|%{
	if ($_.Clientaddress -match "^10." -or $_.Clientaddress -match "^192.168." -or $_.Clientaddress -match "^192.151." -or $_.Clientaddress -match "^192.170."){$subnets.VPN++}
	elseif ($_.Clientaddress -match "^172.16."){$subnets.LAN++}
	elseif($_.Clientaddress.split(".")[0] -eq "172" -and [int]($_.Clientaddress.split(".")[1]) -gt 16){$subnets.VPN++}
	else{$subnets.WAN++}
}
$keys=$subnets|select -expand keys
$values=$subnets|select -expand values
For ($i=0;$i -lt $subnets.Count;$i++){
$body="citrix7subnets,farm=XenApp7,subnet=$($keys[$i]) count=$($values[$i])i"
$body
write-influxDB "monitoringdb" $body
}
#CITRIX APPLICATIONS
$xasessions|?{$_.applicationsinuse}|select -expand applicationsinuse|group|%{
	$body="citrix7apps,farm=XenApp7,app=$($_.name -replace('\\','/') -replace(' ','\ ')) count=$($_.count)i"
	$body
	write-influxDB "monitoringdb" $body
	}
