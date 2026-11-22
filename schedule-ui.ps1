. (Join-Path $PSScriptRoot 'outage-model.ps1')
. (Join-Path $PSScriptRoot 'schedule-view.ps1')
. (Join-Path $PSScriptRoot 'schedule-changes.ps1')
$script:scheduleChangePath=Join-Path $PSScriptRoot 'schedule-alerts.json'
$script:outageAlertPath=Join-Path $PSScriptRoot 'outage-alerts.json'
Read-OutageAlertState




$scheduleWorker={
 param($directory,$now)
 try{
  $python=(Get-Command python.exe -ErrorAction Stop).Source
  $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$python
  $info.Arguments='"'+(Join-Path $directory 'schedule_client.py')+'" --now "'+$now+'"'
  $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.StandardOutputEncoding=[Text.Encoding]::UTF8
  $info.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
  $proc=[Diagnostics.Process]::new();$proc.StartInfo=$info
  try{
   [void]$proc.Start();$stdout=$proc.StandardOutput.ReadToEndAsync();$stderr=$proc.StandardError.ReadToEndAsync();$proc.StandardInput.Close()
   if(!$proc.WaitForExit(60000)){$proc.Kill();throw 'Schedule request timeout'}
   if($proc.ExitCode -ne 0){throw 'Schedule reader failed'}
   $stdout.Result | ConvertFrom-Json
  }finally{$proc.Dispose()}
 }catch{[pscustomobject]@{Ok=$false;error='Не удалось обновить график ЦЕК. Попробуй позже.'}}
}
function Update-ScheduleJob {
 if($script:scheduleJob -and $script:scheduleJob.State -in @('Completed','Failed','Stopped')){
  $result=Receive-Job $script:scheduleJob -ErrorAction SilentlyContinue;Remove-Job $script:scheduleJob;$script:scheduleJob=$null
  if($result -and $result.Ok){
   $script:scheduleData=$result
   if(!$script:disableOutageNotifications){Update-ScheduleChanges $result (Get-KyivNow)}
  }
  elseif($script:scheduleData -and $script:scheduleData.Ok){$script:scheduleData.cached=$true;$script:scheduleData | Add-Member NoteProperty error 'Нет связи с Telegram' -Force}
  elseif($result){$script:scheduleData=$result}
  $script:nextSchedulePoll=[datetime]::Now.AddMinutes(5)
  Render-Schedule
 }
 $ui.ScheduleRefresh.IsEnabled=($null -eq $script:scheduleJob)
 if($script:scheduleStarted -and !$script:scheduleJob -and [datetime]::Now -ge $script:nextSchedulePoll){
  # Date is explicitly Kyiv time; include its real UTC offset for publication dates.
  $zone=[TimeZoneInfo]::FindSystemTimeZoneById('FLE Standard Time');$utc=[datetime]::UtcNow
  $local=[TimeZoneInfo]::ConvertTimeFromUtc($utc,$zone);$stamp=[DateTimeOffset]::new($local,$zone.GetUtcOffset($utc)).ToString('o')
  $ui.ScheduleRefresh.IsEnabled=$false
  $script:scheduleJob=Start-Job -ScriptBlock $scheduleWorker -ArgumentList $script:helperDir,$stamp
 }
 $minute=(Get-KyivNow).ToString('yyyy-MM-dd HH:mm')
 if($script:activeTab -eq 'Schedule' -and $minute -ne $script:scheduleRenderedMinute){$script:scheduleRenderedMinute=$minute;Render-Schedule}
}
$ui.TabStation.Add_Click({Show-ScheduleTab 'Station'})
$ui.TabSchedule.Add_Click({Show-ScheduleTab 'Schedule'})
$ui.DayToday.Add_Click({$script:scheduleView='Today';Render-Schedule})
$ui.DayTomorrow.Add_Click({$script:scheduleView='Tomorrow';Render-Schedule})
$ui.DayLatest.Add_Click({$script:scheduleView='Latest';Render-Schedule})
$ui.ScheduleRefresh.Add_Click({$script:nextSchedulePoll=[datetime]::MinValue;$ui.ScheduleMeta.Text='Обновление…'})
$ui.ScheduleOpenSource.Add_Click({Start-Process $script:scheduleSource})
$ui.ScheduleOpenChannel.Add_Click({Start-Process 'https://t.me/s/cek_info'})
$ui.OutageOpenSchedule.Add_Click({Show-ScheduleTab 'Schedule'})
$ui.StationDetailsToggle.Add_Click({
 $open=$ui.StationDetails.Visibility -ne 'Visible'
 $ui.StationDetails.Visibility=if($open){'Visible'}else{'Collapsed'}
 $ui.StationDetailsToggle.Content=if($open){'Свернуть'}else{'Подробнее'}
 $ui.StationDetailsToggle.Tag=if($open){'Open'}else{$null}
 Update-WidgetLayout
})
$ui.ScheduleDetailsToggle.Add_Click({
 $open=$ui.ScheduleDetails.Visibility -ne 'Visible'
 $ui.ScheduleDetails.Visibility=if($open){'Visible'}else{'Collapsed'}
 $ui.ScheduleDetailsToggle.Content=if($open){'Свернуть'}else{'Подробнее'}
 $ui.ScheduleDetailsToggle.Tag=if($open){'Open'}else{$null}
 Render-Schedule
})
$w.Add_ContentRendered({Update-WidgetLayout})
$ui.ScheduleTimeline.Add_SizeChanged({if($_.WidthChanged){$script:scheduleRenderedMinute=$null}})
$cache=Join-Path $PSScriptRoot 'schedule-cache.json'
if(Test-Path -LiteralPath $cache){try{$script:scheduleData=Get-Content -LiteralPath $cache -Raw -Encoding UTF8 | ConvertFrom-Json;$script:scheduleData.cached=$true}catch{}}
if(!$Check -and !$script:disableOutageNotifications){Initialize-ScheduleChanges $script:scheduleData (Get-KyivNow)}
