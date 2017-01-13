#Monitor server time with w32tm command
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load influxdb functions
import-module $scriptPath\influxDBfunctions.psm1

#servidores NTP a los que consultar la hora
$ntpservers="servercendc02.sistemaswin.com,serverpnadc03.sistemaswin.com,serverpnadc04.sistemaswin.com,serverbpnadc05.beta.sistemaswin.com"

$result=w32tm /monitor /computers:$ntpservers
#parseo el resultado
$result|%{
    if ($_ -match ":123")
    {
    $server= $_.split('[')[0].trim().split(".")[0]
    $server
    }
    elseif($_ -cmatch "NTP:")
    {
    $endpos=
    $secs=$_.substring(0,$_.indexof("s")).split(":")[1].trim() -replace('\+')
    $secs
    $body="ntpserverstime,servername=$server secs=$secs"
    $body
    write-influxDB "monitoringdb" $body
    }
}