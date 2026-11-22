$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'notification-preferences.ps1')
. (Join-Path $PSScriptRoot 'outage-model.ps1')
. (Join-Path $PSScriptRoot 'schedule-changes.ps1')
$script:notificationSettingsPath=Join-Path $PSScriptRoot 'notification-settings-test.json'
$script:outageAlertPath=Join-Path $PSScriptRoot 'outage-alert-preferences-test.json'
$script:scheduleChangePath=Join-Path $PSScriptRoot 'schedule-change-preferences-test.json'
$script:outageAlertSent=@{};$script:outageNotices=0;$script:changeNotices=0
function Show-OutageNotification($event,$lead,$now){$script:outageNotices++;return $true}
function Show-ScheduleChangeNotification($changes,$now){$script:changeNotices++;return $true}
function Assert-Equal($actual,$expected,$message){if($actual -ne $expected){throw $message}}
function Data-At($now,$start=720){
 ('{"Ok":true,"cached":false,"checkedAt":"'+$now.ToString('yyyy-MM-ddTHH:mm:ss')+'+03:00","days":[{"date":"2026-10-18","intervals":[['+$start+',840]],"mentioned":true,"ambiguous":false,"postId":1}],"unparsed":[]}') | ConvertFrom-Json
}
try{
 $script:notificationPrefs=Get-NotificationDefaults
 foreach($key in @('LowBattery','TwoHours','FifteenMinutes','ScheduleChanges')){Assert-Equal (Test-NotificationEnabled $key) $true 'Default disabled'}
 Assert-Equal (Test-NotificationEnabled 'CustomReminder') $false 'Custom reminder should start disabled'
 foreach($key in @('LowBattery','TwoHours','FifteenMinutes','ScheduleChanges','CustomReminder')){$script:notificationPrefs[$key]=$false}
 Save-NotificationPreferences;Read-NotificationPreferences
 foreach($key in @('LowBattery','TwoHours','FifteenMinutes','ScheduleChanges','CustomReminder')){Assert-Equal (Test-NotificationEnabled $key) $false 'Disabled choice not restored'}
 $now=[datetime]'2026-10-18T10:00:00';Update-OutageNotifications (Data-At $now) $now
 $now=[datetime]'2026-10-18T11:45:00';Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:outageNotices 0 'Disabled reminders still notify'
 $script:notificationPrefs.FifteenMinutes=$true
 Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:outageNotices 1 'Enabled 15m reminder did not notify'
 $script:notificationPrefs.FifteenMinutes=$false;$script:notificationPrefs.TwoHours=$true;$script:outageAlertSent=@{}
 $now=[datetime]'2026-10-18T10:00:00';Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:outageNotices 2 'Enabled 2h reminder did not notify independently'
 $now=[datetime]'2026-10-18T11:45:00';Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:outageNotices 2 'Disabled 15m reminder notified'
 Initialize-ScheduleChanges $null $now
 Update-ScheduleChanges (Data-At $now) $now
 Assert-Equal $script:changeNotices 0 'Disabled schedule changes notified'
 $script:notificationPrefs.ScheduleChanges=$true
 Update-ScheduleChanges (Data-At $now) $now
 Assert-Equal $script:changeNotices 0 'Enabling changes caused old publication alert'
 Update-ScheduleChanges (Data-At $now 750) $now
 Assert-Equal $script:changeNotices 1 'Enabled schedule changes did not notify'
 # Unknown/new options and malformed saved values retain safe defaults.
 '{"TwoHours":false,"LowBattery":"false"}' | Set-Content -LiteralPath $script:notificationSettingsPath -Encoding UTF8
 Read-NotificationPreferences
 Assert-Equal (Test-NotificationEnabled 'TwoHours') $false 'False value not loaded'
 Assert-Equal (Test-NotificationEnabled 'LowBattery') $true 'Malformed value overwrote default'
 Assert-Equal (Test-NotificationEnabled 'FifteenMinutes') $true 'New option lost default'
 'PASS: preferences persist, independent reminder types, schedule changes, no catch-up spam, invalid values'
}finally{
 foreach($path in @($script:notificationSettingsPath,$script:outageAlertPath,$script:scheduleChangePath)){
  Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ($path+'.tmp') -ErrorAction SilentlyContinue
 }
}
