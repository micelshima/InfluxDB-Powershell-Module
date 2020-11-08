#Monitor server time with w32tm command
#Mikel V
#load influxdb functions
import-module "$PSscriptroot\..\..\InfluxDB-Powershell-Module"

#servidores NTP a los que consultar la hora
$ntpservers="servercendc02.sistemaswin.com,serverpnadc03.sistemaswin.com,serverpnadc04.sistemaswin.com,serverbpnadc05.sistemaswin.com"

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
