#Monitor subnets connections from clients in Citrix Farm
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load citrix snappin
."$env:programfiles\Citrix\XenApp 6.5 Server SDK\Citrix.XenApp.Sdk.ps1"
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1
$collection=get-xasession -full|?{$_.clientipv4 -ne ''}|select clientipv4 -unique
$LAN=$VPN=$WAN=0
foreach($object in $collection)
{
	if ($object.clientipv4 -match "^10." -or $object.clientipv4 -match "^192.168."){$VPN++}
	if ($object.clientipv4 -match "^172.16."){$LAN++}
	elseif($object.clientipv4.split(".")[0] -eq "172" -and [int]($object.clientipv4.split(".")[1]) -gt 16 -and [int]($object.clientipv4.split(".")[1]) -le 31){$VPN++}
		else{$WAN++}


}
$body="citrixsubnets,farm=XenApp65 lan=$($LAN)i,wan=$($WAN)i,vpn=$($VPN)i"
$body
write-influxDB "monitoringdb" $body