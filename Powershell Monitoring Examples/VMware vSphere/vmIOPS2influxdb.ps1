#Check VM IOPS and write latency in VCenter
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load powercli snappin
if (!(Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
    Add-PSSnapin VMware.VimAutomation.Core
}
#cargo las funciones de influxdb
import-module $scriptPath\influxDBfunctions.psm1 -ErrorAction Stop
$myVC = "servervc1.sistemaswin.com"
$hostpwd='put here your root password encoded with key below'
$hostcred = New-Object System.Management.Automation.PSCredential ("root", (ConvertTo-SecureString $hostpwd -key (1..16)))
Set-PowerCLIConfiguration -DefaultVIServerMode Single -InvalidCertificateAction Ignore -Confirm:$false
$VCServer = Connect-VIserver -server $myVC
$vmhosts=get-vmhost|?{$_.connectionstate -eq "Connected" -and $_.Powerstate -eq "PoweredOn"}|select name
Disconnect-VIServer -server $myVC -Confirm:$False
foreach($vmhost in $vmhosts)
{
write-host $vmhost.name -fore cyan
$HostServer = Connect-VIserver -server $vmhost.name -cred $hostcred
$now=get-date
$starttime=$now.addminutes(-60)
$datastores=@()
Get-Datastore|?{$_.Name -cmatch "^DS" -or $_.Name -cmatch "^3PARPNA0"}|select Name,id|sort name|%{
	$ds=""|select name,id,wwn,type,cpd,entorno
	$ds.type="-"
	$ds.name=$_.name
    $ds.id=$_.id
	$ds.wwn=($_|get-view).Info.Vmfs.Extent[0].DiskName
	if ($ds.name -match "NL"){$ds.type="NL"}
	if ($ds.name -match "FC"){$ds.type="FC"}
	if ($ds.name -cmatch "_PPG"){$ds.type="PP"}
	if ($ds.name -cmatch "_RCG"){$ds.type="RC"}
	if ($ds.name -match "Sol" -or $ds.name -match "^3PARPNA02"){$ds.CPD="AS"}else{$ds.CPD="AE"}
	if ($ds.name -match "Ofimatica" -or $ds.name -match "_ESXOFI_"){$ds.entorno="Ofimatica"}
	if ($ds.name -match "Produccion" -or $ds.name -match "_ESXPRO_"){$ds.entorno="Produccion"}	
    $datastores+=$ds
	}#fin foreach datastore
write-host "Datastore Array collected"
Get-VM -server $vmhost.name -erroraction silentlycontinue|?{$_.PowerState -eq "PoweredOn"}|%{
		foreach($item in $_.datastoreIdlist)
		{
		$ds=$datastores|?{$_.id -eq $item}
			if ($ds -ne $null)
			{
			$iopsavg=$iopsmax=$latency=0
			$wval = Get-Stat $_ -stat "datastore.numberWriteAveraged.average" -Start $starttime -Finish $now -erroraction silentlycontinue|?{$item -match $_.instance} | select -expandproperty Value | measure -average -max
			$rval = Get-Stat $_ -stat "datastore.numberReadAveraged.average" -Start $starttime -Finish $now -erroraction silentlycontinue |?{$item -match $_.instance} | select -expandproperty Value | measure -average -max
			$lval = Get-Stat $_ -stat "disk.maxTotalLatency.latest" -Start $starttime -Finish $now | select -expandproperty Value | measure -max
				if ($wval -ne $null)
				{
				$iopsavg=[math]::round($rval.average + $wval.average,2)
				$iopsmax=[math]::round($rval.maximum + $wval.maximum,2)
				$latency=$lval.maximum
				$body="vmiops,datastore=$($ds.name),cpd=$($ds.cpd),entorno=$($ds.entorno),type=$($ds.type),host=$($vmhost.name),vm=$($_.name) iopsavg=$iopsavg,iopsmax=$iopsmax,latency=$($latency)i"
				$body
				write-influxDB "monitoringdb" $body
				}
			}#fin ds ne null
		}#fin datastoreidlist
	}#fin get-vm
	
Disconnect-VIServer -server $vmhost.name -Confirm:$False
}#fin hosts

