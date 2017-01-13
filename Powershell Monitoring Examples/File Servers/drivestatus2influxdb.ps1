#Monitor server drives
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1 -ErrorAction Stop
#load file with drives to care about in the failover cluster
$cluster=import-csv $scriptPath\clusterdrives.csv -delimiter "`t"
$objFSO = New-Object -com  Scripting.FileSystemObject
$drives=gwmi Win32_logicalDisk -filter "drivetype=3"
	foreach($drive in $drives|?{($cluster|select -expand drive) -contains $_.deviceid})
	{
	$clustername=($cluster|?{$_.drive -eq $Drive.deviceid}).server
	$sizeGB=[math]::round($Drive.Size/1GB,1)
	$freeGB=[math]::round($Drive.freespace/1GB,1)
	$oscysfolder="$($Drive.deviceid)\OSCYS"
	if (test-path $oscysfolder){$oscysSizeGB = [math]::round(($objFSO.GetFolder($oscysfolder).Size)/1GB,0)}
	else{$oscysSizeGB=0}
	$body="drivestatus,technology=3PAR,scope=NAC,location=Madrid,servername=$clustername,drive=$($Drive.deviceid) size=$sizeGB,free=$freeGB,oscys=$oscysSizeGB"
	$body
	write-influxDB "monitoringdb" $body
	}