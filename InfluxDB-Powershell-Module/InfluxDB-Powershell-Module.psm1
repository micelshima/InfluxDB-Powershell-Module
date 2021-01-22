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
	#write-host $url -fore cyan
	if ($PSVersionTable.PSVersion.Major -lt 3) { Invoke-HttpMethod -Uri $url -Body $lineprotocol -method "Post" }
	else { Invoke-webrequest -UseBasicParsing -Uri $url -Body $lineprotocol -method Post }
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
function Invoke-HttpMethod {
	[CmdletBinding()]
	Param(
		[string] $URI,
		[string] $Body,
		[string] $Method

	)
	[Int] $MethodRetryWaitSecond = 6
	[Int] $MaxMethodRetry = 2

	#check flags
	[Bool] $MethodResult = $True

	For ($WriteRetryCount = 0; $WriteRetryCount -lt $MaxMethodRetry; $WriteRetryCount++) {

		$WebRequest = [System.Net.WebRequest]::Create($URI)
		$WebRequest.ContentType = "application/x-www-form-urlencoded"
		$BodyStr = [System.Text.Encoding]::UTF8.GetBytes($Body)
		$Webrequest.ContentLength = $BodyStr.Length
		$WebRequest.ServicePoint.Expect100Continue = $false
		$webRequest.Method = $Method


		# [System.Net.WebRequest]::GetRequestStream()
		Try {
			$RequestStream = $WebRequest.GetRequestStream()

			# [System.IO.Stream]::Write()
			Try {
				$RequestStream.Write($BodyStr, 0, $BodyStr.length)
			}
			Catch [Exception] {
				Write-Error $Error[0].Exception.ErrorRecord
				$MethodResult = $False
			}
			$MethodResult = $True

		}
		Catch [Exception] {
			Write-Error $Error[0].Exception.ErrorRecord
			$MethodResult = $False
		}
		Finally {
			$RequestStream.Close()
		}

		# [System.Net.WebRequest]::GetResponse()
		If ($MethodResult) {
			Try {
				[System.Net.WebResponse] $resp = $WebRequest.GetResponse();
				$MethodResult = $True
			}
			Catch [Exception] {
				Write-Error $Error[0].Exception.ErrorRecord
				$MethodResult = $False
			}
		}

		# [System.Net.WebResponse]::GetResponseStream()
		If ($MethodResult) {
			Try {
				$rs = $resp.GetResponseStream();
				$MethodResult = $True
			}
			Catch [Exception] {
				Write-Error $Error[0].Exception.ErrorRecord
				$MethodResult = $False
			}
		}

		# [System.IO.StreamReader]::ReadToEnd()
		If ($MethodResult) {
			Try {
				[System.IO.StreamReader] $sr = New-Object System.IO.StreamReader -argumentList $rs;
				[string] $results = $sr.ReadToEnd();
				$MethodResult = $True
			}
			Catch [Exception] {
				Write-Error $Error[0].Exception.ErrorRecord
				$MethodResult = $False
			}
			Finally {
				$sr.Close();
			}
		}

		If ($MethodResult) {
			#finally success
			return $results;
		}
		Else {
			#eventually fails
			If ($WriteRetryCount -lt $MaxMethodRetry) {
				#preparation for retry
				Write-Verbose "retries the writing"
				Remove-Variable RequestStream
				Remove-Variable BodyStr
				Remove-Variable WebRequest
				#[System.GC]::Collect([System.GC]::MaxGeneration)
				Start-Sleep -Seconds $MethodRetryWaitSecond
			}
			Else {
				#reached the maximum number of retries
				Write-Verbose "It has reached the maximum number of retries. Skips"
			}
		}
	} #For .. (WriteRetry) .. Loop
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
