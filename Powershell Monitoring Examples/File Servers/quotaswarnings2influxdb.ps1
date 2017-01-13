#Monitor quotas that are almost full with the help of FSRM module
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load FSRM module (2012 R2)
import-module FileServerResourceManager -ErrorAction Stop
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1 -ErrorAction Stop
#load file with drives to care about in the failover cluster
$cluster=import-csv $scriptPath\clusterdrives.csv -delimiter "`t"
#load file of paths that I don't care about
$castigados=get-content $scriptPath\LISTANEGRA.txt
#this server
$server=$env:computername.toupper()
$watchout_limit=2 * 1073741824 #2GB
$critical_limit=0.5 * 1073741824 #0,5GB
$watchout_limitU=0.2 * 1073741824 #200 MB para carpetas de usuarios
$critical_limitU=0.1 * 1073741824 #100 MB para carpetas de usuarios
get-fsrmquota -cimsession $server|?{$_.Softlimit -eq $false -and ((($_.usage + $watchout_limit) -gt $_.size -and ($_.path.substring(0,1) -ne "N" -and $_.path -notmatch 'M:\\USUARIOS')) -or (($_.usage + $watchout_limitU) -gt $_.size -and ($_.path.substring(0,1) -eq "N" -or $_.path -match 'M:\\USUARIOS')))}|%{
	if ((($_.usage + $critical_limit) -ge $_.size -and ($_.path.substring(0,1) -ne "N" -and $_.path -notmatch 'M:\\USUARIOS')) -or (($_.usage + $critical_limitU) -ge $_.size -and ($_.path.substring(0,1) -eq "N" -or $_.path -match 'M:\\USUARIOS'))){$warning="2i"}else{$warning="1i"}
	if ($castigados -contains $_.path){$warning="0i"}
	$sizeGB=[math]::round($_.Size/1GB,1)
	$usageGB=[math]::round($_.usage/1GB,1)
	$freeGB=[math]::round(($_.size - $_.usage)/1GB,1)
	$path=$_.path -replace("\\","/")
	$path=$path -replace(" ","\ ")
	$clustername=($cluster|?{$_.drive -eq $path.substring(0,2)}).server
	$body="quotausage,technology=StorSimple,scope=NAC,location=Sarriguren,servername=$clustername,path=$path quota=$sizeGB,used=$usageGB,free=$freeGB,warning=$warning"
	$body
	write-influxDB "monitoringdb" $body
	}
