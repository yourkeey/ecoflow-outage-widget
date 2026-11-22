function Get-ScheduleVersions($data,$now){
 if(!$data -or !$data.Ok){return}
 foreach($day in $data.days){
  try{$date=[datetime]::ParseExact($day.date,'yyyy-MM-dd',$null)}catch{continue}
  if($date -lt $now.Date -or $date -gt $now.Date.AddDays(1)){continue}
  $parts=@($day.date,[string][bool]$day.mentioned,[string][bool]$day.ambiguous)
  foreach($range in $day.intervals){$parts+=([string]$range[0]+'-'+[string]$range[1])}
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join '|')))).Replace('-','')}finally{$sha.Dispose()}
  [pscustomobject]@{Date=$day.date;Hash=$hash;Day=$day}
 }
}
function Save-ScheduleChangeState {
 try{
  $days=@(foreach($date in $script:scheduleVersions.Keys){@{date=$date;hash=$script:scheduleVersions[$date]}})
  $temporary=$script:scheduleChangePath+'.tmp'
  @{version=1;days=$days} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $script:scheduleChangePath -Force
 }catch{}
}
function Initialize-ScheduleChanges($data,$now){
 $script:scheduleVersions=@{}
 $loaded=$false
 if(Test-Path -LiteralPath $script:scheduleChangePath){try{
  $state=Get-Content -LiteralPath $script:scheduleChangePath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($state.version -eq 1){foreach($day in $state.days){$script:scheduleVersions[[string]$day.date]=[string]$day.hash};$loaded=$true}
 }catch{}}
 if(!$loaded){
  # The already displayed cache is the initial baseline, not a new publication.
  foreach($item in @(Get-ScheduleVersions $data $now)){$script:scheduleVersions[$item.Date]=$item.Hash}
  Save-ScheduleChangeState
 }
}
function Show-ScheduleChangeNotification($changes,$now){
 if(!$script:tray){return $false}
 $hasUpdate=@($changes | Where-Object Kind -eq 'Updated').Count -gt 0
 $title=if($hasUpdate){'ЦЕК · график изменился'}else{'ЦЕК · появился график'}
 $lines=@(foreach($item in $changes){
  $day=$item.Day
  $date=[datetime]::ParseExact($item.Date,'yyyy-MM-dd',$null)
  $label=if($date -eq $now.Date){'Сегодня'}else{'Завтра'}
  $ranges=@(foreach($range in $day.intervals){(Format-ScheduleMinute $range[0])+'–'+(Format-ScheduleMinute $range[1])})
  $text=if($day.ambiguous){'нужна проверка исходного поста'}elseif(!$day.mentioned){'черга 2.2 не указана, проверь пост'}elseif($ranges.Count){$ranges -join ', '}else{'интервалы отключений не указаны'}
  $label+' '+$date.ToString('dd.MM')+': '+$text
 })
 $body='Черга 2.2'+"`n"+($lines -join "`n")+"`nОткрой виджет, чтобы посмотреть расписание."
 if($body.Length -gt 250){$body=$body.Substring(0,210)+"…`nПодробности — в виджете."}
 $script:tray.ShowBalloonTip(12000,$title,$body,[Windows.Forms.ToolTipIcon]::Info)
 return $true
}
function Update-ScheduleChanges($data,$now){
 if(!$data -or !$data.Ok -or $data.cached){return}
 $changes=@()
 foreach($item in @(Get-ScheduleVersions $data $now)){
  if(!$script:scheduleVersions.ContainsKey($item.Date)){
   $changes+=[pscustomobject]@{Date=$item.Date;Hash=$item.Hash;Day=$item.Day;Kind='New'}
  }elseif($script:scheduleVersions[$item.Date] -ne $item.Hash){
   $changes+=[pscustomobject]@{Date=$item.Date;Hash=$item.Hash;Day=$item.Day;Kind='Updated'}
  }
 }
 if($changes.Count -eq 0){return}
 if(!(Test-NotificationEnabled 'ScheduleChanges')){
  foreach($item in $changes){$script:scheduleVersions[$item.Date]=$item.Hash}
  Save-ScheduleChangeState;return
 }
 if(Show-ScheduleChangeNotification $changes $now){
  foreach($item in $changes){$script:scheduleVersions[$item.Date]=$item.Hash}
  foreach($date in @($script:scheduleVersions.Keys)){try{if([datetime]$date -lt $now.Date.AddDays(-3)){$script:scheduleVersions.Remove($date)}}catch{}}
  Save-ScheduleChangeState
 }
}
