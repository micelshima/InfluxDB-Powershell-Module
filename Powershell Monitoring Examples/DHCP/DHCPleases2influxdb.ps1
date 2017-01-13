#Monitor DHCP leases
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1
$server=$env:computername.toupper()
$result=netsh dhcp server \\$server show mibinfo
$inuse = ($result | where-object {$_-match "No. of Addresses in use = "}|%{$_.Split('=')[-1].Trim( ).Trim(".").Trim(" ")})
$free = ($result | where-object {$_-match "No. of free Addresses = "}|%{$_.Split('=')[-1].Trim().Trim(".").Trim(" ")})

$total = ([int]$inuse+[int]$free)
$body="dhcpleases,location=Sarriguren,servername=$server total=$total,free=$free,inuse=$inuse"
$body
write-influxDB "monitoringdb" $body