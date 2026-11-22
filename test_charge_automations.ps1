$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$layout=[Windows.Markup.XamlReader]::Parse((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'notification-settings.xaml') -Raw -Encoding UTF8))
if($layout.FindName('AutoHigh').Tag -ne 'High' -or $layout.FindName('AutoLow').Tag -ne 'Low'){throw 'Automation settings controls missing'}
. (Join-Path $PSScriptRoot 'charge-automations.ps1')
function Get-Metric($data,$keys){foreach($key in $keys){$v=$data.$key;if($null -ne $v){return [double]$v}};return $null}
function Assert-Target($soc,$limit,$high,$low,$expected){
 $data=[pscustomobject]@{'pd.soc'=$soc;'mppt.cfgChgWatts'=$limit}
 $actual=Get-ChargeAutomationTarget $data @{High=$high;Low=$low}
 if($actual -ne $expected){throw "Unexpected target for SOC=$soc limit=$limit : $actual"}
}
Assert-Target 90 770 $true $true 50
Assert-Target 100 770 $true $true 50
Assert-Target 89 770 $true $true $null
Assert-Target 40 50 $true $true 770
Assert-Target 0 50 $true $true 770
Assert-Target 41 50 $true $true $null
Assert-Target 90 50 $true $true $null
Assert-Target 40 770 $true $true $null
Assert-Target 90 770 $false $true $null
Assert-Target 40 50 $true $false $null
Assert-Target -1 50 $true $true $null
Assert-Target 101 50 $true $true $null
Assert-Target 90 $null $true $true $null
Assert-Target ([double]::NaN) 50 $true $true $null
$script:chargeAutomationPath=Join-Path $PSScriptRoot 'charge-automations-test.json'
try{
 Read-ChargeAutomationPreferences
 if($script:chargeAutomationPrefs.High -or $script:chargeAutomationPrefs.Low){throw 'Rules must start disabled'}
 $script:chargeAutomationPrefs.High=$true;Save-ChargeAutomationPreferences
 Read-ChargeAutomationPreferences
 if(!$script:chargeAutomationPrefs.High -or $script:chargeAutomationPrefs.Low){throw 'Preferences not restored'}
 '{"High":"true","Low":true}' | Set-Content -LiteralPath $script:chargeAutomationPath -Encoding UTF8
 Read-ChargeAutomationPreferences
 if($script:chargeAutomationPrefs.High -or !$script:chargeAutomationPrefs.Low){throw 'Invalid preference was accepted'}
 $script:chargeAutomationPrefs=@{High=$true;Low=$true}
 $script:cfg=[pscustomobject]@{Mode='Private'};$script:authBlocked=$false;$script:job=$null
 $script:stationData=[pscustomobject]@{'pd.soc'=90;'mppt.cfgChgWatts'=770}
 $script:lastUpdate=[datetime]::Now;$script:chargeAutomationNextAttempt=[datetime]::MinValue;$script:commands=@()
 function Start-StationCommand($operation,$watts,$enabled){$script:commands+=@([pscustomobject]@{Op=$operation;Watts=$watts})}
 Update-ChargeAutomations;Update-ChargeAutomations
 if($script:commands.Count -ne 1 -or $script:commands[0].Watts -ne 50){throw 'Missing command or repeated command during cooldown'}
 $script:chargeAutomationNextAttempt=[datetime]::MinValue;$script:lastUpdate=[datetime]::Now.AddMinutes(-2)
 Update-ChargeAutomations
 if($script:commands.Count -ne 1){throw 'Command used stale readings'}
 $script:lastUpdate=[datetime]::Now;$script:cfg.Mode='Public';Update-ChargeAutomations
 if($script:commands.Count -ne 1){throw 'Command ran for unsupported connection'}
 'PASS: thresholds, disabled rules, persistence, unchanged limits, cooldown, stale data and connection mode'
}finally{
 Remove-Item -LiteralPath $script:chargeAutomationPath -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath ($script:chargeAutomationPath+'.tmp') -ErrorAction SilentlyContinue
}
