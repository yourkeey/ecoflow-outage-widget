$script:chargeAutomationPrefs=@{High=$false;Low=$false}
$script:chargeAutomationNextAttempt=[datetime]::MinValue
function Read-ChargeAutomationPreferences {
 $script:chargeAutomationPrefs=@{High=$false;Low=$false}
 if(Test-Path -LiteralPath $script:chargeAutomationPath){try{
  $saved=Get-Content -LiteralPath $script:chargeAutomationPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($key in @('High','Low')){
   $property=$saved.PSObject.Properties[$key]
   if($property -and $property.Value -is [bool]){$script:chargeAutomationPrefs[$key]=$property.Value}
  }
 }catch{}}
}
function Save-ChargeAutomationPreferences {
 $temporary=$script:chargeAutomationPath+'.tmp'
 $script:chargeAutomationPrefs | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
 Move-Item -LiteralPath $temporary -Destination $script:chargeAutomationPath -Force
}
function Get-ChargeAutomationTarget($data,$preferences){
 if(!$data -or !$preferences){return $null}
 try{
  $soc=Get-Metric $data @('bms_emsStatus.lcdShowSoc','pd.soc','bms_bmsStatus.soc')
  $limit=Get-Metric $data @('mppt.cfgChgWatts')
 }catch{return $null}
 if($null -eq $soc -or $null -eq $limit -or [double]::IsNaN($soc) -or [double]::IsInfinity($soc) -or $soc -lt 0 -or $soc -gt 100 -or [double]::IsNaN($limit) -or [double]::IsInfinity($limit) -or $limit -lt 50 -or $limit -gt 870){return $null}
 if($preferences.High -eq $true -and $soc -ge 90 -and $limit -ne 50){return 50}
 if($preferences.Low -eq $true -and $soc -le 40 -and $limit -ne 770){return 770}
 return $null
}
function Update-ChargeAutomations {
 if(!$script:cfg -or $script:cfg.Mode -ne 'Private' -or $script:authBlocked -or $script:job -or !$script:stationData -or !$script:lastUpdate -or ([datetime]::Now-$script:lastUpdate).TotalSeconds -ge 90 -or [datetime]::Now -lt $script:chargeAutomationNextAttempt){return}
 $target=Get-ChargeAutomationTarget $script:stationData $script:chargeAutomationPrefs
 if($null -eq $target){return}
 # Retry at most every five minutes, including if the worker cannot start.
 $script:chargeAutomationNextAttempt=[datetime]::Now.AddMinutes(5)
 Start-StationCommand 'SetAcChargingPower' $target $null
}
