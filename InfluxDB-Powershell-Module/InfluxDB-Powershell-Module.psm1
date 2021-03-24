function convertto-unixtime {
	param(
		[datetime]$DateTime,
		[switch]$seconds
	)
	[datetime]$EpochOrigin = "1970/01/01 00:00:00"
	if ($seconds) {
		if ($DateTime -eq $null)
		{ $unixtime = [int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End ([DateTime]::Now).ToUniversalTime()).Totalseconds }
		else { $unixtime = [int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End (Get-Date $DateTime).ToUniversalTime()).Totalseconds }
	}
	else {
		if ($DateTime -eq $null)
		{ $miliseconds = [int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End ([DateTime]::Now).ToUniversalTime()).TotalMilliseconds }
		else { $miliseconds = [int64](New-TimeSpan -Start (Get-Date $EpochOrigin) -End (Get-Date $DateTime).ToUniversalTime()).TotalMilliseconds }
		#convert milliseconds to nanoseconds
		$unixtime = $miliseconds * 1000000
	}
	return $unixtime
}
Function convertto-datetime($unixtime) {
	#convert nanoseconds to milliseconds
	$miliseconds = $unixtime / 1000000
	[datetime]$EpochOrigin = "1970/01/01 00:00:00"
	$datetime = (get-date $EpochOrigin).AddMilliseconds($miliseconds)

	return $datetime.tostring("dd/MM/yyyy HH:mm:ss")
}
function write-influxDB() {
	param(
		[parameter(Position = 0,
			Mandatory = $true)]
		[string]$database,

		[parameter(Position = 1,Mandatory = $true,ValueFromPipeline)]
		[string]$lineprotocol,

		[parameter(Position = 2)]
		[string]$server = "serverinfluxdb01.sistemaswin.com"
	)


	$url = "http://{0}:8086/write?db={1}" -f $server, $database	
	Invoke-webrequest -UseBasicParsing -Uri $url -Body $lineprotocol -method Post
}
Function Write-SecuredInfluxDB{
	param(
		[parameter(Position = 0,
			Mandatory = $true)]
		[string]$database,
		[parameter(Position = 1,Mandatory = $true,ValueFromPipeline)]
		[string]$lineprotocol,
		[parameter(Position = 2)]
		[string]$server = "serverinfluxdb01.sistemaswin.com",
		[string]$username,
		[string]$password,
		[PScredential]$credential
	)
	$url = "https://{0}:8086/write?db={1}" -f $server, $database
	if (-not $credential){
	$pass = ConvertTo-SecureString -String $password -asPlainText -Force
	$credential = New-Object System.Management.Automation.PSCredential -ArgumentList $username,$pass
	}
	if($PSVersionTable.PSVersion.Major -lt 7){
		# Código para ignorar el certificado de https de influx
		$code= @"
			using System.Net;
			using System.Security.Cryptography.X509Certificates;
			public class TrustAllCertsPolicy : ICertificatePolicy {
				public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {
					return true;
				}
			}
"@
		Add-Type -TypeDefinition $code -Language CSharp
		[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
		# Fin codigo de ignorado certificado https
		Invoke-webrequest -UseBasicParsing -Uri $url -Body $lineprotocol -method Post -Credential $credential
	}
	else{
		Invoke-webrequest -UseBasicParsing -Uri $url -Body $lineprotocol -method Post -Credential $credential -SkipCertificateCheck
	}
}
Function write-InfluxLogging(){
	param(
		[int]$errorcode,
		[int]$duration,
		[Parameter(ValueFromPipeline)]
		[string]$msg
	)
	$arrayfieldset=@()
	$arrayfieldset+='value=1i'
	if ($errorcode){$arrayfieldset+='errorcode={0}i' -f $errorcode}
	if ($duration){$arrayfieldset+='duration={0}i' -f $duration}
	if ($msg){$arrayfieldset+='msg="{0}"' -f $msg}
	$fieldset=$arrayfieldset -join ","
	$measurement='powershell'
	$tagset= 'servername={0},username={1},script={2}' -f $env:computername.toupper(),$env:username,((split-path $MyInvocation.scriptname -leaf) -replace " ","\ ")
	$body="$measurement,$tagset $fieldset"
	write-influxdb "logs" $body
}

function read-influxDB() {
	param(
		[parameter(Position = 0,
			Mandatory = $true)]
		[string]$database,

		[parameter(Position = 1,Mandatory = $true,ValueFromPipeline)]
		[string]$query,

		[parameter(Position = 2)]
		[string]$server = "serverinfluxdb01.sistemaswin.com"
	)


	$url = "http://{0}:8086/query?db={1}" -f $server, $database
	$body = "q=$query"
	$result = Invoke-webrequest -UseBasicParsing -Uri $url -Body $body -method Post
	$content = convertfrom-json -input $result.content
	$columns = $content.results.series.columns
	$objects = new-object System.Collections.Arraylist
	foreach ($singlepoint in $content.results.series.values) {
		$object = New-Object PSObject
		for ($j = 0; $j -lt $columns.length; $j++) {
			$object | Add-Member -MemberType NoteProperty -Name $columns[$j] -Value $singlepoint[$j]
		}
		[void]$objects.add($object)
	}
	return $objects
}
