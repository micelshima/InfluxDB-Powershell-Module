#Monitor receiver version from clients in Citrix Farm
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load citrix snappin
."$env:programfiles\Citrix\XenApp 6.5 Server SDK\Citrix.XenApp.Sdk.ps1"
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1

$collection=get-xasession -full|?{$_.clientproductid -eq 1}|select @{label="ver";expression={$_.clientversion.split(".")[0]}}|group ver
foreach($object in $collection)
{
	if ($object.name -eq ''){$version="n/a"}else{$version=$object.name}
$body="citrixversions,farm=XenApp65,version=$version count=$($object.count)i"
$body
write-influxDB "reportingdb" $body
}