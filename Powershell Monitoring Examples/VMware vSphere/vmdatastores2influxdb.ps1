#Check datastore usage in VCenter
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load powercli snappin
if (!(Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
    Add-PSSnapin VMware.VimAutomation.Core
}
#load influxdb functions
import-module "$PSscriptroot\..\..\InfluxDB-Powershell-Module"
$myVC = "servervc1.sistemaswin.com"
Set-PowerCLIConfiguration -DefaultVIServerMode Single -InvalidCertificateAction Ignore -Confirm:$false
$VCServer = Connect-VIserver -server $myVC 
Get-Datastore|?{$_.Name -cmatch "^DS" -or $_.Name -cmatch "^3PARPNA0"}| Sort Name|%{

$dsname=$_.name
$sizeGB=[Math]::Round(($_.ExtensionData.Summary.Capacity)/1GB,0)

$freeGB=[Math]::Round(($_.ExtensionData.Summary.freespace)/1GB,0)
#reservation of 10% equals to Available storage
$available=$_.ExtensionData.Summary.freespace -($_.ExtensionData.Summary.Capacity/10)
$availableGB=[Math]::Round($available/1GB,0)
$type=$CPD=$entorno="-"
if ($dsname -match "NL"){$type="NL"}
if ($dsname -match "FC"){$type="FC"}
if ($dsname -cmatch "_PPG"){$type="PP"}
if ($dsname -cmatch "_RCG"){$type="RC"}
if ($dsname -match "Sol" -or $dsname -match "^3PARPNA02"){$CPD="AS"}else{$CPD="AE"}
if ($dsname -match "Ofimatica" -or $dsname -match "_ESXOFI_"){$entorno="Ofimatica"}
if ($dsname -match "Produccion"  -or $dsname -match "_ESXPRO_"){$entorno="Produccion"}
#write-host "$dsname $sizeGB $freeGB $availableGB"
	$body="vmdatastores,datastore=$dsname,cpd=$cpd,entorno=$entorno,type=$type size=$sizeGB,free=$freeGB,available=$availableGB"
	$body
	write-influxDB "monitoringdb" $body
}
Disconnect-VIServer $myVC -Confirm:$False
