# InfluxDB query with Powershell
# Mikel V. 29/12/2016
#resize the window
$pshost = get-host
$pswindow = $pshost.ui.rawui
$newsize = $pswindow.windowsize
$bnewsize = $pswindow.buffersize
$newsize.width = 150
$newsize.height = 55
$bnewsize.width=$newsize.width
$pswindow.buffersize=$bnewsize
$pswindow.windowsize = $newsize
#####window resized######
write-host ''
write-host '  8888888           .d888 888                    8888888b.  888888b.  '
write-host '    888            d88P"  888                    888  "Y88b 888  "88b '
write-host '    888            888    888                    888    888 888  .88P '
write-host '    888   88888b.  888888 888  888  888 888  888 888    888 8888888K. '
write-host '    888   888 "88b 888    888  888  888  Y8bd8P  888    888 888  "Y88b'
write-host '    888   888  888 888    888  888  888   X88K   888    888 888    888'
write-host '    888   888  888 888    888  Y88b 888 .d8""8b. 888  .d88P 888   d88P'
write-host '  8888888 888  888 888    888   "Y88888 888  888 8888888P"  8888888P" '
write-host ''
import-module "$PSscriptroot\InfluxDB-Powershell-Module"
$raya= "-" * 40
do
{
write-host "`nDATABASES" -fore cyan
write-host $raya -fore cyan
read-influxdb "_internal" "SHOW DATABASES"|?{$_.name}|%{write-host $_.name -fore cyan}
$database=read-host "database"
	if ($database -ne 'exit')
	{
		do
		{
		write-host "`nMEASUREMENTS IN $($database.toupper())" -fore cyan
		write-host $raya -fore cyan
		$measurements=read-influxdb $database "SHOW MEASUREMENTS"|?{$_.name}|select -expand name
		$measurements|%{write-host $_ -fore cyan}
		$qry=read-host "InfluxQL query"
			if ($qry -ne 'exit')
			{			
			if($qry -match "delete" -and $qry -notmatch "where"){write-host "NO BORRES TODA LA TABLA!!" -fore yellow}
			else{
				if ($measurements -contains $qry){$qry="select * from $qry"}
				$object=read-influxdb $database $qry
				$object|ft * -auto
				}
			}
		}while($qry -ne "exit")
	}
}while($database -ne "exit") 
