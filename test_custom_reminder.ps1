$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'outage-model.ps1')
$script:notificationSettingsPath=Join-Path $PSScriptRoot 'custom-reminder-preferences-test.json'
$script:outageAlertPath=Join-Path $PSScriptRoot 'custom-reminder-alerts-test.json'
$script:notificationPrefs=Get-NotificationDefaults;$script:outageAlertSent=@{};$script:notices=@()
function Show-OutageNotification($event,$lead,$now){$script:notices+=@{Lead=$lead;At=$now};return $true}
function Assert-Equal($actual,$expected,$message){if($actual -ne $expected){throw $message}}
function Data-At($now){
 ('{"Ok":true,"cached":false,"checkedAt":"'+$now.ToString('yyyy-MM-ddTHH:mm:ss')+'+03:00","days":[{"date":"2026-10-18","intervals":[[720,840]],"mentioned":true,"ambiguous":false,"postId":1}],"unparsed":[]}') | ConvertFrom-Json
}
try{
 foreach($case in @(@('0','1',1),@('1','30',90),@('24','0',1440))){Assert-Equal (ConvertTo-CustomLeadMinutes $case[0] $case[1]) $case[2] 'Valid custom duration rejected'}
 foreach($case in @(@('0','0'),@('1','60'),@('24','1'),@('25','0'),@('-1','0'),@('a','30'),@('1',''),@('','5'))){if($null -ne (ConvertTo-CustomLeadMinutes $case[0] $case[1])){throw 'Invalid custom duration accepted'}}
 $script:notificationPrefs.CustomReminder=$true;$script:notificationPrefs.CustomMinutes=45
 $script:notificationPrefs.TwoHours=$false;$script:notificationPrefs.FifteenMinutes=$false
 Save-NotificationPreferences;Read-NotificationPreferences
 Assert-Equal (Get-CustomLeadMinutes) 45 'Custom time not persisted'
 Assert-Equal (Test-NotificationEnabled 'CustomReminder') $true 'Custom toggle not persisted'
 $now=[datetime]'2026-10-18T11:14:59';Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 0 'Custom reminder fired early'
 $now=[datetime]'2026-10-18T11:15:00';Update-OutageNotifications (Data-At $now) $now
 Update-OutageNotifications (Data-At $now.AddSeconds(1)) $now.AddSeconds(1)
 Assert-Equal $script:notices.Count 1 'Custom threshold missing or duplicate'
 Assert-Equal $script:notices[0].Lead 45 'Wrong custom threshold'
 $script:outageAlertSent=@{};Read-OutageAlertState
 Update-OutageNotifications (Data-At $now.AddMinutes(1)) $now.AddMinutes(1)
 Assert-Equal $script:notices.Count 1 'Custom reminder repeated after restart'
 $script:notificationPrefs.CustomReminder=$false;$script:outageAlertSent=@{}
 Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 1 'Disabled custom reminder fired'
 # Coincident built-in and custom leads generate exactly one delivery.
 $script:notificationPrefs=Get-NotificationDefaults;$script:notificationPrefs.CustomReminder=$true;$script:notificationPrefs.CustomMinutes=120
 $script:outageAlertSent=@{};$script:notices=@();$now=[datetime]'2026-10-18T10:00:00'
 Update-OutageNotifications (Data-At $now) $now;Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 1 'Duplicate coincident reminders'
 # A late publication gives the closest due reminder and suppresses older leads.
 $script:notificationPrefs.CustomMinutes=60;$script:outageAlertSent=@{};$script:notices=@();$now=[datetime]'2026-10-18T11:50:00'
 Update-OutageNotifications (Data-At $now) $now;Update-OutageNotifications (Data-At $now) $now
 Assert-Equal $script:notices.Count 1 'Late publication generated a notification burst'
 Assert-Equal $script:notices[0].Lead 15 'Late publication did not select urgent threshold'
 'PASS: custom duration, boundaries, save/load, threshold, deduplication, restart, disabled, collisions, late publication'
}finally{
 foreach($path in @($script:notificationSettingsPath,$script:outageAlertPath)){Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ($path+'.tmp') -ErrorAction SilentlyContinue}
}
