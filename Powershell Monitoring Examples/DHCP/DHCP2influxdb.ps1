#cargo las funciones de influxdb
import-module $PSscriptroot\..\..\InfluxDB-Powershell-Module
$content=import-csv "$Psscriptroot\DHCP2influxdb.csv" -delimiter "`t"
foreach ($item in $content){
$skip=$false
$failovercluster=get-dhcpserverv4failover -computername $item.server
	if ($failovercluster)
	{
	$server=$failovercluster.name
	if ($item.server -match "02$" -and $failovercluster.State -ne 'PartnerDown'){$skip=$true}
	}
else{$server=$item.server.toupper()}
if($skip -eq $false){
$result=Get-DhcpServerv4Statistics -computername $item.server
$inuse = $result.AddressesInUse
$free = $result.AddressesAvailable
$total = $result.TotalAddresses
$body="dhcpleases,location=$($item.location),servername=$server total=$total,free=$free,inuse=$inuse"
$body
write-influxDB "monitoringdb" $body
}
}