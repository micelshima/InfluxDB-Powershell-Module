#Monitor quotas for history purposes with the help of FSRM module
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load FSRM module (2012 R2)
import-module FileServerResourceManager -ErrorAction Stop
#load influxdb functions
import-module "$PSscriptroot\..\..\InfluxDB-Powershell-Module"
#load file with drives to care about in the failover cluster
$info=import-csv "$scriptPath\clusterdrives.csv" -delimiter "`t"
$hoy=get-date -uformat "%Y/%m/%d"
$mes=get-date -uformat "%Y-%m"
$servers="SERVER01A","SERVER01B"
$quotas=get-fsrmquota -cimsession $servers
foreach ($quota in $quotas)
{
$unidad=$quota.path.substring(0,2)
$clfserver=($info|?{$_.drive -eq $unidad}).server
$MBquota=[math]::truncate($quota.size/1MB)
$MBused=[math]::truncate($quota.usage/1MB)
$GBused=[math]::round($quota.usage/1GB,2)
$path=$quota.path -replace("\\","/")
$path=$path -replace(" ","\ ")
out-file ".\logs\Quotas_$mes.csv" -input "$hoy;$unidad;$($quota.path);$MBquota;$MBused" -append
$body="quotausage,technology=StorSimple,scope=NAC,location=Sarriguren,servername=$clfserver,path=$path used=$GBused"
$body
write-influxDB "historydb" $body
}
