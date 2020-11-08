#Check new VM's and deleted VM's in VCenter
#Mikel V
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
#load influxdb functions
import-module "$PSscriptroot\..\..\InfluxDB-Powershell-Module"
#load powercli snappin
if (!(Get-PSSnapin VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
    Add-PSSnapin VMware.VimAutomation.Core
}
$LastDays=60
$VC="servervc1.sistemaswin.com"
Set-PowerCLIConfiguration -DefaultVIServerMode Single -InvalidCertificateAction Ignore -Confirm:$false
$VCServer = Connect-VIserver -server $VC
 
 $EventFilterSpecByTime = New-Object VMware.Vim.EventFilterSpecByTime
    If ($LastDays)
    {
        $EventFilterSpecByTime.BeginTime = (get-date).AddDays(-$LastDays)
    }
    $EventFilterSpec = New-Object VMware.Vim.EventFilterSpec
    $EventFilterSpec.Time = $EventFilterSpecByTime
    $EventFilterSpec.DisableFullMessage = $False
    $EventFilterSpec.Type = "VmCreatedEvent","VmDeployedEvent","VmClonedEvent","VmDiscoveredEvent","VmRegisteredEvent","VmRemovedEvent"
    $EventManager = Get-View EventManager
    $NewVmTasks = $EventManager.QueryEvents($EventFilterSpec)
 
    Foreach ($Task in $NewVmTasks)
    {
	$unixtime=convertto-unixtime $Task.CreatedTime
	$username=$Task.UserName -replace("\\","/")
	$servername=$Task.Vm.name
	$event="creation"
	if ($servername -match "_"){$n="0i"}else{$n="1i"}
		if ($Task -is [Vmware.vim.VmRemovedEvent])
		{
		$event="deletion"
		$n="-$n"
		}
	$body="vmcreationdeletion,location=Sarriguren,vcenter=$VC,servername=$servername,username=$username,event=$event n=$n $unixtime"
	$body	
	write-influxDB "reportingdb" $body
    }
Disconnect-VIServer $VC -Confirm:$False
