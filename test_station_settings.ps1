$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'notification-settings.ps1')
function Get-Metric($data,$keys){foreach($key in $keys){$v=$data.$key;if($null -ne $v){return [double]$v}};return $null}
$controls=@{}
foreach($name in @('ChargeSlider','XBoost','ChargeChoice','ChargeCurrent','XBoostCurrent','ChargeApply','Connection','StationControlStatus')){
 $controls[$name]=[pscustomobject]@{Value=50.0;Text='';IsChecked=$false;IsEnabled=$false}
}
$script:stationDialog=[pscustomobject]@{IsLoaded=$true;Controls=$controls}
$script:stationDialog | Add-Member ScriptMethod FindName {param($name) $this.Controls[$name]}
$script:cfg=[pscustomobject]@{Mode='Private'};$script:authBlocked=$false;$script:job=$null
$script:lastUpdate=[datetime]::Now;$script:stationStatus=$null;$script:stationCommand=$null;$script:stationSliderDirty=$false
$script:stationData=[pscustomobject]@{'mppt.cfgChgWatts'=500;'mppt.cfgAcXboost'=1}
Update-StationSettings
if($controls.ChargeSlider.Value -ne 500 -or !$controls.XBoost.IsChecked -or !$controls.XBoost.IsEnabled -or $controls.ChargeApply.IsEnabled){throw 'Reported settings did not initialize controls'}
$controls.ChargeSlider.Value=700;$script:stationSliderDirty=$true
Update-StationSettings
if($controls.ChargeSlider.Value -ne 700 -or !$controls.ChargeApply.IsEnabled){throw 'Pending slider choice was overwritten'}
$script:job=[pscustomobject]@{State='Running'};$script:stationCommand='SetXBoost'
Update-StationSettings
if($controls.ChargeSlider.IsEnabled -or $controls.XBoost.IsEnabled -or $controls.Connection.IsEnabled){throw 'Controls not locked during command'}
$script:job=$null;$script:stationCommand=$null;$script:stationData=[pscustomobject]@{'mppt.cfgChgWatts'=500}
Update-StationSettings
if($controls.XBoost.IsEnabled -or $controls.XBoost.IsChecked -or $controls.XBoostCurrent.Text -notmatch '—'){throw 'Unknown X-Boost treated as confirmed'}
$script:lastUpdate=[datetime]::Now.AddMinutes(-2);Update-StationSettings
if($controls.ChargeSlider.IsEnabled -or $controls.XBoost.IsEnabled){throw 'Stale data enabled controls'}
$script:lastUpdate=[datetime]::Now;$script:cfg.Mode='Public';Update-StationSettings
if($controls.ChargeSlider.IsEnabled -or $controls.XBoost.IsEnabled){throw 'Unsupported mode enabled controls'}
'PASS: station settings initial state, pending slider, command lock, unknown and stale values'
