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

function read-influxDB {

	param(
		[parameter(Position = 0,
			Mandatory = $true)]
		[string]$database,

		[parameter(Position = 1,Mandatory = $true,ValueFromPipeline)]
		[string]$query,

		[parameter(Position = 2)]
		[string]$server = "serverinfluxdb01.sistemaswin.com",
		[PSCredential]$credential
	)

	$url = "http://{0}:8086/query?db={1}&q={2}" -f  $server,$database,$query
	if($credential){
		$Results = Invoke-RestMethod -Uri $Url -credential $credential -AllowUnencryptedAuthentication
	}
	else{
		$Results = Invoke-RestMethod -Uri $Url
	}

	if($Results.results.error){write-error $Results.results.error}
	else{
		$measurement=$Results.results.series.name
		$columns=$Results.results.series.columns
		$data = [System.Collections.ArrayList]@()
		if($Results.results.series.tags){
			$tags=$Results.results.series[0].tags
			$t1=$tags[0]
			$keys=get-variable -name t1|select -expand value|gm|?{$_.MemberType -eq "NoteProperty"}|select -expand name

		}

		foreach($s in $Results.results.series){

			foreach($v in $s.values){
			$item=@{}
				for ($i=0;$i -lt $columns.count;$i++){
					if($columns[$i] -eq "time"){$item.add($columns[$i],[datetime]$v[$i]) }
					else{$item.add($columns[$i],$v[$i])}
				}
				if($tags){
				if($keys.count -eq 1){$item.add($keys,$s.tags.$keys)}
				else{
					for ($j=0;$j -lt $keys.count;$j++){
						$item.add($keys[$j],$s.tags.$($keys[$j]))
					}
				}

				}
				$null = $data.add([pscustomobject]$item)
			}

		}
		return $data
	}
}
Function convertto-lineprotocol{
	param(
		[string]$measurement,
		[pscustomobject]$data
	)
	$d1=$data[0]
	$keys=get-variable -name d1|select -expand value|gm|?{$_.MemberType -eq "NoteProperty"}|select -expand name
	$series=[System.Collections.ArrayList]@()
	$measurement|write-host -fore cyan
	foreach($key in $keys){'{0} -> {1}'-f $key,$d1.$key.gettype().name|out-host}
	foreach($item in $data){
		$tags=$values=@()
		foreach($key in $keys){
			if($d1.$key.gettype().name -eq "String"){$tags+='{0}={1}' -f $key,$item.$key -replace ' ','\ '}
			elseif($d1.$key.gettype().name -in "Decimal","Int32","Int64","Double"){$values+='{0}={1}' -f $key,$item.$key -replace ',','.'}
			elseif($d1.$key.gettype().name -eq "DateTime"){$time=convertto-unixtime $item.$key}
		}
		$line='{0},{1} {2} {3}' -f $measurement,($tags -join ","),($values -join ","),$time
		$null=$series.add($line)
	}
	return $series
}
