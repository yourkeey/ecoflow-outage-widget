. (Join-Path $PSScriptRoot 'notification-preferences.ps1')
function Get-KyivNow {[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([datetime]::UtcNow,'FLE Standard Time')}
function Format-ScheduleMinute($minute){'{0:00}:{1:00}' -f [math]::Floor([int]$minute/60),([int]$minute%60)}
function Format-OutageCountdown($span){
 $seconds=[math]::Max(0,[int][math]::Ceiling($span.TotalSeconds))
 '{0:00}:{1:00}:{2:00}' -f [math]::Floor($seconds/3600),([math]::Floor($seconds/60)%60),($seconds%60)
}
function Get-OutageEvents($data,$now){
 if(!$data -or !$data.Ok){return}
 foreach($day in $data.days){
  if(!$day.mentioned -or $day.ambiguous){continue}
  try{$date=[datetime]::ParseExact($day.date,'yyyy-MM-dd',$null)}catch{continue}
  if($date -lt $now.Date -or $date -gt $now.Date.AddDays(1)){continue}
  foreach($range in $day.intervals){
   if($range.Count -ne 2 -or [int]$range[0] -lt 0 -or [int]$range[1] -gt 1440 -or [int]$range[0] -ge [int]$range[1]){continue}
   $start=$date.AddMinutes([int]$range[0]);$end=$date.AddMinutes([int]$range[1])
   [pscustomobject]@{Start=$start;End=$end;Day=$day;Key=('2.2|'+$start.ToString('yyyy-MM-ddTHH:mm'));Range=((Format-ScheduleMinute $range[0])+' — '+(Format-ScheduleMinute $range[1]))}
  }
 }
}
function Test-OutageSourceFresh($data,$day,$now){
 if(!$data -or !$data.Ok -or $data.cached -or !$day -or !$day.mentioned -or $day.ambiguous){return $false}
 try{$checked=[DateTimeOffset]::Parse($data.checkedAt).DateTime;$age=($now-$checked).TotalMinutes}catch{return $false}
 if($age -lt -2 -or $age -gt 15){return $false}
 if(@($data.unparsed | Where-Object {[int]$_.postId -gt [int]$day.postId}).Count -gt 0){return $false}
 return $true
}
function Get-OutageContext($data,$now){
 $events=@(Get-OutageEvents $data $now | Sort-Object Start)
 $current=$events | Where-Object {$_.Start -le $now -and $_.End -gt $now} | Select-Object -First 1
 $next=$events | Where-Object Start -gt $now | Select-Object -First 1
 $today=$null
 if($data -and $data.Ok){$today=$data.days | Where-Object date -eq $now.ToString('yyyy-MM-dd') | Select-Object -First 1}
 $event=if($current){$current}else{$next}
 [pscustomobject]@{Current=$current;Next=$next;Today=$today;Event=$event;Trusted=(Test-OutageSourceFresh $data $(if($event){$event.Day}else{$today}) $now)}
}
function Read-OutageAlertState {
 $script:outageAlertSent=@{}
 if(Test-Path -LiteralPath $script:outageAlertPath){try{
  $saved=Get-Content -LiteralPath $script:outageAlertPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($item in $saved.sent){$script:outageAlertSent[[string]$item.key]=[string]$item.at}
 }catch{}}
}
function Save-OutageAlertState($now){
 try{
  $sent=@(foreach($key in @($script:outageAlertSent.Keys)){
   try{$age=($now-[datetime]::Parse($script:outageAlertSent[$key])).TotalDays}catch{$age=100}
   if($age -le 3){@{key=$key;at=$script:outageAlertSent[$key]}}else{$script:outageAlertSent.Remove($key)}
  })
  $temporary=$script:outageAlertPath+'.tmp'
  @{sent=$sent} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $script:outageAlertPath -Force
 }catch{}
}
function Show-OutageNotification($event,$lead,$now){
 if(!$script:tray){return $false}
 $minutes=[math]::Max(1,[int][math]::Ceiling(($event.Start-$now).TotalMinutes))
 $remaining=if($minutes -ge 60){'{0} ч {1:00} мин' -f [math]::Floor($minutes/60),($minutes%60)}else{"$minutes мин"}
 $day=if($event.Start.Date -eq $now.Date){'сегодня'}else{'завтра'}
 $title=if($lead -le 15){'ЦЕК · отключение совсем скоро'}else{'ЦЕК · подготовься к отключению'}
 $body="Черга 2.2: $day $($event.Range). До отключения $remaining. По опубликованному графику."
 $script:tray.ShowBalloonTip(12000,$title,$body,[Windows.Forms.ToolTipIcon]::Warning)
 return $true
}
function Update-OutageNotifications($data,$now){
 $context=Get-OutageContext $data $now
 $event=$context.Next
 if(!$event -or !(Test-OutageSourceFresh $data $event.Day $now)){return}
 $minutes=($event.Start-$now).TotalMinutes
 if($minutes -le 0){return}
 $due=@()
 if($minutes -le 120 -and $minutes -gt 15 -and (Test-NotificationEnabled 'TwoHours')){$due+=120}
 if($minutes -le 15 -and (Test-NotificationEnabled 'FifteenMinutes')){$due+=15}
 $custom=Get-CustomLeadMinutes
 if($minutes -le $custom -and (Test-NotificationEnabled 'CustomReminder')){$due+=$custom}
 $pending=@($due | Sort-Object -Unique | Where-Object {!$script:outageAlertSent.ContainsKey($event.Key+'|'+$_)})
 if(!$pending.Count){return}
 $lead=[int]$pending[0]
 $key=$event.Key+'|'+$lead
 if($script:outageAlertSent.ContainsKey($key)){return}
 if(Show-OutageNotification $event $lead $now){
  $script:outageAlertSent[$key]=$now.ToString('o')
  $thresholds=@(120,15)
  if(Test-NotificationEnabled 'CustomReminder'){$thresholds+=$custom}
  foreach($threshold in $thresholds){if($threshold -ge $lead){$script:outageAlertSent[$event.Key+'|'+$threshold]=$now.ToString('o')}}
  Save-OutageAlertState $now
 }
}
