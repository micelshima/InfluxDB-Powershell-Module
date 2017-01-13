#Monitor application usage in Citrix Farm
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load citrix snappin
."$env:programfiles\Citrix\XenApp 6.5 Server SDK\Citrix.XenApp.Sdk.ps1"
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1
$collection=get-xasession -full|?{$_.clientproductid -eq 1 -and $_.state -eq "Active" -and $_.applicationstate -eq "Active"}|select browsername|group browsername

foreach($object in $collection)
{
$app=$object.name -replace(" ","\ ")
$body="citrixapps,farm=XenApp65,app=$app count=$($object.count)i"
$body
write-influxDB "monitoringdb" $body
}


	
