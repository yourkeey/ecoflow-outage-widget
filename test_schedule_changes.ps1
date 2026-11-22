$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'outage-model.ps1')
. (Join-Path $PSScriptRoot 'schedule-changes.ps1')
$script:scheduleChangePath=Join-Path $PSScriptRoot 'schedule-alerts-test.json'
$script:changeNotices=@()
function Show-ScheduleChangeNotification($changes,$now){$script:changeNotices+=,@($changes);return $true}
function Make-Data($ranges='[[900,1020]]',$date='2026-10-18'){
 ('{"Ok":true,"cached":false,"checkedAt":"2026-10-18T12:00:00+03:00","days":[{"date":"'+$date+'","intervals":'+$ranges+',"mentioned":true,"ambiguous":false,"postId":100}],"unparsed":[]}') | ConvertFrom-Json
}
function Assert-Equal($actual,$expected,$message){if($actual -ne $expected){throw $message}}
$now=[datetime]'2026-10-18T12:00:00'
try{
 Initialize-ScheduleChanges (Make-Data '[[900,1020]]' '2026-10-17') $now
 Assert-Equal $script:changeNotices.Count 0 'Archive or initialization notified'
 $data=Make-Data
 Update-ScheduleChanges $data $now
 Assert-Equal $script:changeNotices.Count 1 'New schedule did not notify'
 Assert-Equal $script:changeNotices[0][0].Kind 'New' 'New kind incorrect'
 $data.days[0].postId=101;$data.checkedAt='2026-10-18T12:05:00+03:00'
 Update-ScheduleChanges $data $now
 Assert-Equal $script:changeNotices.Count 1 'Repost or check timestamp triggered a duplicate'
 $changed=Make-Data '[[960,1080]]'
 Update-ScheduleChanges $changed $now
 Assert-Equal $script:changeNotices.Count 2 'Changed intervals did not notify'
 Assert-Equal $script:changeNotices[1][0].Kind 'Updated' 'Update kind incorrect'
 $script:scheduleVersions=@{};Initialize-ScheduleChanges $changed $now
 Update-ScheduleChanges $changed $now
 Assert-Equal $script:changeNotices.Count 2 'Duplicate after restart'
 $offline=Make-Data '[[1000,1100]]';$offline.cached=$true
 Update-ScheduleChanges $offline $now
 Assert-Equal $script:changeNotices.Count 2 'Offline cache caused notification'
 Update-ScheduleChanges (Make-Data '[[1000,1100]]' '2026-10-17') $now
 Assert-Equal $script:changeNotices.Count 2 'Archive caused notification'
 $tomorrow=Make-Data '[[600,720]]' '2026-10-19'
 Update-ScheduleChanges $tomorrow $now
 Assert-Equal $script:changeNotices.Count 3 'Tomorrow publication did not notify'
 $cancelled=Make-Data '[]'
 Update-ScheduleChanges $cancelled $now
 Assert-Equal $script:changeNotices.Count 4 'Interval cancellation did not notify'
 # No toast on upgrade for an already known current cache.
 Remove-Item -LiteralPath $script:scheduleChangePath
 $script:changeNotices=@();Initialize-ScheduleChanges $data $now;Update-ScheduleChanges $data $now
 Assert-Equal $script:changeNotices.Count 0 'Initial existing schedule generated a fake new post alert'
 'PASS: new schedule, edits, reposts, timestamps, restart, offline, archive, tomorrow, cancellation, upgrade baseline'
}finally{Remove-Item -LiteralPath $script:scheduleChangePath -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ($script:scheduleChangePath+'.tmp') -ErrorAction SilentlyContinue}
