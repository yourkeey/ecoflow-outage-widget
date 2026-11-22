$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'notification-preferences.ps1')
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.ps1') -Raw
$tokens=$null;$parseErrors=$null
$tree=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors){throw 'PowerShell syntax error'}
foreach($name in @('Save-AlertState','Update-LowChargeAlert')){
 $node=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 Invoke-Expression $node.Extent.Text
}
function Show-LowChargeNotification($soc){$script:notifications++}
$script:alertPath=Join-Path $PSScriptRoot 'alerts-test.json'
$script:alertDevice='';$script:lowChargeNotified=$false;$script:notifications=0
$script:cfg=[pscustomobject]@{Serial='TEST-STATION-A'}
try{
 foreach($value in @($null,[double]::NaN,[double]::PositiveInfinity,-1,101,20,25)){Update-LowChargeAlert $value}
 if($script:notifications -ne 0){throw 'Invalid data or 20% triggered notification'}
 foreach($value in @(19,18,15,20,24,19)){Update-LowChargeAlert $value}
 if($script:notifications -ne 1){throw 'Repeated notification below 25%'}
 # Simulate restart and reload the persisted state.
 $script:alertDevice='';$script:lowChargeNotified=$false
 Update-LowChargeAlert 18
 if($script:notifications -ne 1){throw 'Notification repeated after restart'}
 Update-LowChargeAlert 25;Update-LowChargeAlert 19
 if($script:notifications -ne 2){throw 'Notification did not rearm at 25%'}
 $script:cfg.Serial='TEST-STATION-B';Update-LowChargeAlert 19
 if($script:notifications -ne 3){throw 'New station inherited previous station alert'}
 $script:notificationPrefs.LowBattery=$false;$script:cfg.Serial='TEST-STATION-C';Update-LowChargeAlert 19
 if($script:notifications -ne 3){throw 'Disabled low battery notification fired'}
 $script:notificationPrefs.LowBattery=$true;Update-LowChargeAlert 19
 if($script:notifications -ne 4){throw 'Reenabled low battery notification did not fire'}
 'PASS: threshold, invalid data, repeat suppression, restart, rearm, station change'
}finally{Remove-Item -LiteralPath $script:alertPath -ErrorAction SilentlyContinue}
