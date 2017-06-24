#Monitor DHCP leases
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1 -ErrorAction Stop
if ((get-dhcpserverv4failover).name){$server=(Get-DhcpServerv4Failover).name}
else{$server=$env:computername.toupper()}
$result=Get-DhcpServerv4Statistics
$inuse = $result.AddressesInUse
$free = $result.AddressesAvailable
$total = $result.TotalAddresses
$body="dhcpleases,location=Sarriguren,servername=$server total=$total,free=$free,inuse=$inuse"
$body
write-influxDB "monitoringdb" $body