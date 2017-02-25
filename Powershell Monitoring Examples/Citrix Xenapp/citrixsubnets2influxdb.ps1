#Monitor connections in Citrix Farm
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load citrix snappin
."$env:programfiles\Citrix\XenApp 6.5 Server SDK\Citrix.XenApp.Sdk.ps1"
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1
$collection=get-xasession -full|?{$_.clientipv4 -ne ''}|select clientipv4 -unique
$subnets=@{'vpn'=0;'lan'=0;'wan'=0}
foreach($object in $collection)
{
	if ($object.clientipv4 -match "^10." -or $object.clientipv4 -match "^192.168." -or $object.clientipv4 -match "^192.151." -or $object.clientipv4 -match "^192.170."){$subnets.VPN++}
	elseif ($object.clientipv4 -match "^172.16."){$subnets.LAN++}
	elseif($object.clientipv4.split(".")[0] -eq "172" -and [int]($object.clientipv4.split(".")[1]) -gt 16){$subnets.VPN++}
	else{$subnets.WAN++}


}
$keys=$subnets|select -expand keys
$values=$subnets|select -expand values
For ($i=0;$i -lt $subnets.Count;$i++){
$body="citrixsubnets,farm=XenApp65,subnet=$($keys[$i]) count=$($values[$i])i"
$body
write-influxDB "monitoringdb" $body
}
