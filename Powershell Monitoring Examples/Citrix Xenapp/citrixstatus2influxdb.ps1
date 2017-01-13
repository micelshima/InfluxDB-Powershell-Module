#Monitor sessions count in Citrix Farm
#Mikel V
Function get-freespace($server)
{
$reg=""|select server,sizeGB,freeGB,percent
$reg.server=$server
$Disks = gwmi -computername $Server win32_logicaldisk -filter "drivetype=3"
foreach ($Disk in $Disks)  
	{
		if ($Disk.deviceid -eq "C:")
		{
		$reg.sizeGB= [math]::round($Disk.size/1GB,2)
		$Used = ([int64]$Disk.size - [int64]$Disk.freespace)
		$reg.percent = [int](($Used * 100.0)/$Disk.Size)
		$reg.freeGB= [math]::round($Disk.FreeSpace/1GB,2)		
		}
	} #fin del for

return $reg
}
Function get-pendingreboot($server)
{
$pending="0i"
$WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $server
#Making registry connection to the local/remote computer
$RegCon = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey([Microsoft.Win32.RegistryHive]"LocalMachine",$server)
	If ($WMI_OS.BuildNumber -ge 6001)
	{
	$RegSubKeysCBS = $RegCon.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\").GetSubKeyNames()
	$CBSRebootPend = $RegSubKeysCBS -contains "RebootPending"
	If ($CBSRebootPend){$CBS = $true}#End If ($CBSRebootPend)
	}#End If ($WMI_OS.BuildNumber -ge 6001)
#Query WUAU from the registry
$RegWUAU = $RegCon.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")
$RegWUAURebootReq = $RegWUAU.GetSubKeyNames()
$WUAURebootReq = $RegWUAURebootReq -contains "RebootRequired"
#Query PendingFileRenameOperations from the registry
$RegSubKeySM = $RegCon.OpenSubKey("SYSTEM\CurrentControlSet\Control\Session Manager\")
$RegValuePFRO = $RegSubKeySM.GetValue("PendingFileRenameOperations",$null)
						
#Closing registry connection
$RegCon.Close()
if ($CBS -or $WUAURebootReq -or $RegValuePFRO){$pending="1i"}
return $pending
}
Function get-sophoserr($server)
{
$err="0i"
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
return $err
}#fin sophoserr
Function get-maintenanceservers()
{
#cargo template de worker groups
$templatewks=import-csv "$scriptPath\XAmaintenance_template.csv" -delimiter "`t"
$currentwks=get-XAworkergroup|select workergroupname,servernames
$maintenanceservers=@()
$templatewks|group server|sort name|%{
	$prod=$maintenance,$missingwk=$null
	$reg=""|select server,maintenance,missingwk
	$reg.server=$_.name
	foreach ($twk in $_.group)
	{
	$cservers=($currentwks|?{$_.workergroupname -eq $twk.workergroup}).servernames
	#write-host "$($reg.server) $($twk.workergroup)" -fore magenta
	#$cservers
		if ($cservers -contains $reg.server){$prod=1}
		else
		{
		$maintenance=1
		$missingwk="$missingwk;$($twk.workergroup -replace(' '))"
		}
	}
	if($maintenance -eq 1)
	{
		if ($prod -eq 1){$reg.maintenance = "1i"}
		else{$reg.maintenance="2i"}
	}
	else{$reg.maintenance="0i"}
	if ($missingwk -eq $null){$reg.missingwk="-"}
	else{$reg.missingwk="'$($missingwk.substring(1))'"}
	$maintenanceservers+=$reg
	}
return $maintenanceservers
}
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load citrix snappin
."$env:programfiles\Citrix\XenApp 6.5 Server SDK\Citrix.XenApp.Sdk.ps1"
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1
$maintenanceservers=get-maintenanceservers
$maintenanceservers
$citrixlicenses=@()
$XAServers=get-xaServer|select servername|sort servername
$XAServers|%{
	$serverload=""|select server,load,missingwk,maintenance,activesessions,inactivesessions,citrixlicenses,pendingreboot,sophoserr
	$icasessions=get-xasession -servername $_.servername|?{$_.protocol -eq "ica"}
	$serverload.activesessions=($icasessions|?{$_.state -eq "Active"}|measure-object).count
	$serverload.inactivesessions=($icasessions|?{$_.state -eq "Disconnected"}|measure-object).count
	$load=get-xaserverload -servername $_.servername
	$serverload.citrixlicenses=($icasessions|?{$_.state -eq "Active" -and $_.applicationstate -eq "Active" -and $_.browsername -and $citrixlicenses -notcontains $_.accountname}|measure-object).count
	$citrixlicenses+=$icasessions|?{$_.state -eq "Active" -and $_.applicationstate -eq "Active" -and $_.browsername -and $citrixlicenses -notcontains $_.accountname}|select -expand accountname
	$citrixlicenses=$citrixlicenses|select -unique
	$serverload.server=$_.servername
	if ($load -eq $null){$serverload.load=0}
	else{$serverload.load=$load.load}
	$serverload.pendingreboot=get-pendingreboot $serverload.server
	$serverload.sophoserr=get-sophoserr $serverload.server
	$freeGB=(get-freespace $serverload.server).freeGB
	if ($freeGB -eq $null){$freeGB=0}
	$serverstatus=$maintenanceservers|?{$_.server -eq $serverload.server}
		if ($serverstatus -eq $null)
		{
		$serverload.missingwk="-"
		$serverload.maintenance="0i"
		}
		else
		{
		$serverload.missingwk=$serverstatus.missingwk
		$serverload.maintenance=$serverstatus.maintenance
		}
	$body="citrixstatus,farm=XenApp65,servername=$($serverload.server),missingwk=$($serverload.missingwk) activesessions=$($serverload.activesessions),inactivesessions=$($serverload.inactivesessions),load=$($serverload.load),citrixlicenses=$($serverload.citrixlicenses),maintenance=$($serverload.maintenance),pendingreboot=$($serverload.pendingreboot),sophoserr=$($serverload.sophoserr),free=$freeGB"
	$body
	write-influxDB "monitoringdb" $body
	}