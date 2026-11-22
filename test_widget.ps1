$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.ps1') -Raw
$source=$source.Replace('$script:cfg = if (!$Check) { Get-EcoFlowConnection $PSScriptRoot }',@'
$script:cfg=[pscustomobject]@{Mode='Test'}
'@)
$source=$source.Replace('EcoFlowRiverWidget','EcoFlowRiverWidget.Smoke')
$source=$source.Replace('$script:scheduleStarted=$true','$script:scheduleStarted=$false')
$source=$source.Replace('$script:scheduleData=$null','$script:scheduleData=$null;$script:disableOutageNotifications=$true')
$source=$source.Replace("'notification-settings.json'","'notification-settings-ui-test.json'")
$source=$source.Replace("'load-history.json'","'load-history-ui-test.json'")
$tokens=$null;$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors){throw 'Widget syntax error'}
$workerNode=$tree.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$worker'},$true)
$source=$source.Replace($workerNode.Extent.Text,@'
$worker = { [pscustomobject]@{Ok=$true;Data=[pscustomobject]@{'pd.soc'=81;'pd.wattsInSum'=125;'pd.wattsOutSum'=42;'pd.remainTime'=95}} }
'@)
$tree=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
$saveNode=$tree.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-Preferences'},$true)
$source=$source.Replace($saveNode.Extent.Text,'function Save-Preferences {}')
$source=$source.Replace('[void]$script:application.Run($w)',@'
$script:smokeTick=0;$script:smokeFailed=$false;$script:firstTimestamp=$null
$smoke=[Windows.Threading.DispatcherTimer]::new();$smoke.Interval=[timespan]::FromMilliseconds(500)
$smoke.Add_Tick({
 try{
  $script:smokeTick++
  switch($script:smokeTick){
   1 { $w.Hide() }
   2 { if($w.IsVisible){throw 'Hide failed'};Show-Widget }
   3 { if(!$w.IsVisible){throw 'Show failed'};if(!$script:tray.Visible){throw 'Tray missing'} }
   10 {
    if($ui.Soc.Text -ne '81 %'){throw 'Background update failed'}
    if($script:trayValue -ne '81'){throw 'Tray percentage failed'}
    if(!$script:loadSamples.Count -or $script:loadSamples[-1].Watts -ne 42){throw 'Load sample was not recorded'}
    $script:loadTip.IsOpen=$true;Draw-LoadDetails
    if($script:loadTip.FindName('Plot').Children.Count -lt 2){throw 'Load history tooltip failed'}
    $script:loadTip.IsOpen=$false
    $script:firstTimestamp=$script:lastUpdate
    Request-Refresh
    $iconBitmap=$script:trayIcon.ToBitmap();$iconBitmap.Save((Join-Path $PSScriptRoot 'tray-preview.png'));$iconBitmap.Dispose()
   }
   20 {
    if($script:lastUpdate -le $script:firstTimestamp){throw 'Manual refresh failed'}
    $smoke.Stop();'PASS: tray icon, hide/show, live UI mapping, manual refresh, exit';$script:exitRequested=$true;$w.Close()
   }
   12 {
    $today=(Get-KyivNow).ToString('yyyy-MM-dd')
    $stamp=[DateTimeOffset]::Now.ToString('o')
    $script:scheduleData=('{"Ok":true,"cached":false,"checkedAt":"'+$stamp+'","days":[{"date":"'+$today+'","intervals":[[360,480],[1020,1230]],"mentioned":true,"ambiguous":false,"source":"https://t.me/cek_info/1","postId":1}],"unparsed":[]}') | ConvertFrom-Json
    $script:nextSchedulePoll=[datetime]::Now.AddHours(1)
    Show-ScheduleTab 'Schedule'
    if($ui.SchedulePanel.Visibility -ne 'Visible' -or $ui.StationPanel.Visibility -ne 'Collapsed'){throw 'Schedule tab switch failed'}
    if($ui.ScheduleIntervals.Children.Count -ne 2){throw 'Schedule interval cards failed'}
    if($ui.StationIntervalsSection.Visibility -ne 'Visible' -or @($ui.StationIntervals.Children | Where-Object Tag -eq 'OutageInterval').Count -ne 2 -or $ui.StationIntervalsAxis.Children.Count -ne 5){throw 'Station timeline failed'}
    $script:scheduleView='Tomorrow';Render-Schedule
    if($ui.ScheduleCompactValue.Text -ne 'Ожидаем расписание'){throw 'Tomorrow used today schedule'}
    $script:scheduleView='Today';Render-Schedule
    Show-ScheduleTab 'Station'
   }
   14 {$ui.StationDetailsToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
   15 {
    if($ui.StationDetails.Visibility -ne 'Visible'){throw 'Station details toggle failed'}
    if($ui.StationDetailsToggle.Tag -ne 'Open'){throw 'Disclosure icon state failed'}
    $bounds=$ui.Freshness.TransformToAncestor($w).TransformBounds([Windows.Rect]::new(0,0,$ui.Freshness.ActualWidth,$ui.Freshness.ActualHeight))
    if($bounds.Bottom -gt $w.ActualHeight-10){throw 'Station footer clipped'}
    $ui.StationDetailsToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Show-ScheduleTab 'Schedule'
    $ui.ScheduleDetailsToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
   }
   16 {
    if($ui.ScheduleDetails.Visibility -ne 'Visible'){throw 'Schedule details toggle failed'}
    if([math]::Abs($ui.QueueBadge.ActualWidth-$ui.QueueBadge.ActualHeight) -gt 0.75 -or [math]::Abs($ui.QueueBadge.ActualWidth-42) -gt 0.75){throw ('Queue badge stretched: '+$ui.QueueBadge.ActualWidth+' x '+$ui.QueueBadge.ActualHeight)}
    $ui.ScheduleDetailsToggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
    Show-ScheduleTab 'Station'
   }
   17 {
    $script:settingsTestStage=0
    $script:settingsTestTimer=[Windows.Threading.DispatcherTimer]::new();$script:settingsTestTimer.Interval=[timespan]::FromMilliseconds(250)
    $script:settingsTestTimer.Add_Tick({
     try{
      $dialog=[Windows.Application]::Current.Windows | Where-Object Title -eq 'Настройки EcoFlow Widget' | Select-Object -First 1
      if(!$dialog){throw 'Notification settings did not open'}
      if($script:settingsTestStage -eq 0){
       $toggle=$dialog.FindName('TwoHours');$toggle.IsChecked=$false;$toggle.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.CheckBox]::ClickEvent))
       if(Test-NotificationEnabled 'TwoHours'){throw 'Settings toggle did not change preference'}
       $dialog.FindName('CustomHours').Text='1';$dialog.FindName('CustomMinutes').Text='30'
       $dialog.FindName('CustomApply').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
       if(!(Test-NotificationEnabled 'CustomReminder') -or (Get-CustomLeadMinutes) -ne 90){throw 'Custom reminder fields did not apply'}
       $script:settingsTestStage=1
      }else{
       Read-NotificationPreferences
       if(Test-NotificationEnabled 'TwoHours'){throw 'Settings toggle was not saved'}
       if(!(Test-NotificationEnabled 'CustomReminder') -or (Get-CustomLeadMinutes) -ne 90){throw 'Custom reminder was not saved'}
       $script:settingsTestTimer.Stop()
       $dialog.FindName('Done').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
      }
     }catch{
      $script:settingsTestTimer.Stop();$script:smokeFailed=$true;$script:smokeFailure=$_.Exception.Message
      if($dialog){$dialog.Close()}
     }
    })
    $script:settingsTestTimer.Start();Show-NotificationSettings
    if($script:smokeFailed){$smoke.Stop();$script:exitRequested=$true;$w.Close()}
   }
  }
 }catch{
  $script:smokeFailed=$true;$script:smokeFailure=$_.Exception.Message;$smoke.Stop();$script:exitRequested=$true;$w.Close()
 }
})
$smoke.Start()
[void]$script:application.Run($w)
if($script:smokeFailed){Write-Output ('FAIL: '+$script:smokeFailure);exit 1}
Write-Output 'PASS: tray, hide/show, manual refresh, schedule tabs, date selection, interval rendering'
'@)
$temporary=Join-Path $PSScriptRoot 'widget-smoke.ps1'
try{
 [IO.File]::WriteAllText($temporary,$source,[Text.UTF8Encoding]::new($true))
 & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $temporary -StartHidden
 if($LASTEXITCODE -ne 0){throw 'Widget smoke test failed'}
}finally{Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue;Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'notification-settings-ui-test.json') -ErrorAction SilentlyContinue;Remove-Item -LiteralPath (Join-Path $PSScriptRoot 'load-history-ui-test.json') -ErrorAction SilentlyContinue}
