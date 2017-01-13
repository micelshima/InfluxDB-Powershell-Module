function convertto-unixtime($DateTime)
{
[datetime]$EpochOrigin = "1970/01/01 00:00:00"
	if ($DateTime -eq $null)
	{$miliseconds=[int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End ([DateTime]::Now).ToUniversalTime()).TotalMilliseconds}
	else{$miliseconds=[int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End (Get-Date $DateTime).ToUniversalTime()).TotalMilliseconds}
#convert milliseconds to nanoseconds
$unixtime=$miliseconds * 1000000
return $unixtime
}
Function convertto-datetime($unixtime)
{#convert nanoseconds to milliseconds
$miliseconds=$unixtime/1000000
[datetime]$EpochOrigin = "1970/01/01 00:00:00"
$datetime=(get-date $EpochOrigin).AddMilliseconds($miliseconds)

return $datetime.tostring("dd/MM/yyyy HH:mm:ss")
}
function write-influxDB($database,$body)
{
$url="http://serverinfluxdb01.sistemaswin.com:8086/write?db=$database"
Invoke-webrequest -UseBasicParsing -Uri $url -Body $body -method Post
}

function read-influxDB($database,$qry)
{
$url="http://serverinfluxdb01.sistemaswin.com:8086/query?db=$database"
$body="q=$qry"
$result=Invoke-webrequest -UseBasicParsing -Uri $url -Body $body -method Post
$content=convertfrom-json -input $result.content
$columns=$content.results.series.columns
$objects=new-object System.Collections.Arraylist
	foreach ($singlepoint in $content.results.series.values)
	{
	$object=New-Object PSObject
		for ($j=0;$j -lt $columns.length;$j++)
		{        
		$object|Add-Member -MemberType NoteProperty -Name $columns[$j] -Value $singlepoint[$j]
		}
	[void]$objects.add($object)
	}
return $objects
}