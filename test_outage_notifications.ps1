$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'outage-model.ps1')
$script:outageAlertPath=Join-Path $PSScriptRoot 'outage-alerts-test.json'
$script:outageAlertSent=@{};$script:notices=@()
function Show-OutageNotification($event,$lead,$now){$script:notices+=@{Lead=$lead;Key=$event.Key};return $true}
function Data-At($now,$start=720,$end=840){
 $date=$now.ToString('yyyy-MM-dd');$stamp=$now.ToString('yyyy-MM-ddTHH:mm:ss')+'+03:00'
 ('{"Ok":true,"cached":false,"checkedAt":"'+$stamp+'","days":[{"date":"'+$date+'","intervals":[['+$start+','+$end+']],"mentioned":true,"ambiguous":false,"postId":100}],"unparsed":[]}') | ConvertFrom-Json
}
function Assert-Equal($actual,$expected,$message){if($actual -ne $expected){throw $message}}
try{
 $now=[datetime]'2026-10-18T09:59:59';$data=Data-At $now
 Update-OutageNotifications $data $now;Assert-Equal $script:notices.Count 0 'Early notification'
 $now=[datetime]'2026-10-18T10:00:00';$data=Data-At $now
 Update-OutageNotifications $data $now;Update-OutageNotifications $data $now.AddSeconds(1)
 Assert-Equal $script:notices.Count 1 'Missing 2h notification or duplicate'
 Assert-Equal $script:notices[0].Lead 120 'Wrong lead'
 # Persisted delivery state must survive a restart.
 $script:outageAlertSent=@{};Read-OutageAlertState
 Update-OutageNotifications $data $now.AddSeconds(2)
 Assert-Equal $script:notices.Count 1 'Duplicate after restart'
 $now=[datetime]'2026-10-18T11:45:00';$data=Data-At $now
 Update-OutageNotifications $data $now;Update-OutageNotifications $data $now.AddMinutes(1)
 Assert-Equal $script:notices.Count 2 'Missing 15m notification or duplicate'
 Assert-Equal $script:notices[1].Lead 15 'Wrong urgent lead'
 $now=[datetime]'2026-10-18T12:01:00';Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 2 'Notification after outage start'
 # A late publication or resume within 15 minutes sends one urgent alert.
 $script:outageAlertSent=@{};$script:notices=@();$now=[datetime]'2026-10-18T11:50:00'
 Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 1 'Late publication burst or lost alert'
 Assert-Equal $script:notices[0].Lead 15 'Late publication should send urgent alert only'
 Assert-Equal $script:outageAlertSent.ContainsKey('2.2|2026-10-18T12:00|120') $true 'Late alert did not suppress old 2h alert'
 # Stale, cached, ambiguous, archived, or superseded sources cannot notify.
 $now=[datetime]'2026-10-18T10:00:00'
 foreach($mode in @('Cached','Stale','Ambiguous','Yesterday','NewUnparsed')){
  $script:outageAlertSent=@{};$script:notices=@();$data=Data-At $now
  switch($mode){
   Cached {$data.cached=$true}
   Stale {$data.checkedAt='2026-10-18T09:00:00+03:00'}
   Ambiguous {$data.days[0].ambiguous=$true}
   Yesterday {$data.days[0].date='2026-10-17'}
   NewUnparsed {$data.unparsed=@([pscustomobject]@{postId=101})}
  }
  Update-OutageNotifications $data $now
  Assert-Equal $script:notices.Count 0 ('Unsafe source notified: '+$mode)
 }
 # A changed start time is a different event; a changed end time isn't.
 $script:outageAlertSent=@{};$script:notices=@();$data=Data-At $now
 Update-OutageNotifications $data $now
 Update-OutageNotifications (Data-At $now 720 870) $now
 Assert-Equal $script:notices.Count 1 'End-time correction repeated alert'
 Update-OutageNotifications (Data-At $now 690 840) $now
 Assert-Equal $script:notices.Count 2 'Rescheduled start did not notify'
 Assert-Equal (Format-OutageCountdown ([timespan]::FromSeconds(7201))) '02:00:01' 'Countdown formatting'
 $context=Get-OutageContext (Data-At ([datetime]'2026-10-18T12:30:00')) ([datetime]'2026-10-18T12:30:00')
 Assert-Equal ([bool]$context.Current) $true 'Active outage not detected'
 'PASS: 2h, 15m, deduplication, restart, resume, stale data, corrections, active outage, timer'
}finally{Remove-Item -LiteralPath $script:outageAlertPath -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ($script:outageAlertPath+'.tmp') -ErrorAction SilentlyContinue}
