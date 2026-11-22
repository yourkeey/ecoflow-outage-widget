function Update-StationSettings {
 $d=$script:stationDialog
 if(!$d -or !$d.IsLoaded){return}
 $slider=$d.FindName('ChargeSlider');$toggle=$d.FindName('XBoost')
 $fresh=($null -ne $script:stationData -and $null -ne $script:lastUpdate -and ([datetime]::Now-$script:lastUpdate).TotalSeconds -lt 90)
 $ready=($fresh -and $script:cfg -and $script:cfg.Mode -eq 'Private' -and !$script:authBlocked -and !$script:job)
 $limit=$null;$boost=$null
 if($fresh){
  $limit=Get-Metric $script:stationData @('mppt.cfgChgWatts')
  $boost=Get-Metric $script:stationData @('mppt.cfgAcXboost')
 }
 if($null -eq $limit -or $limit -lt 50 -or $limit -gt 870){$limit=$null}
 if($null -eq $boost -or $boost -notin @(0,1)){$boost=$null}
 $script:stationUpdating=$true
 try{
  if(!$script:stationSliderDirty -and $null -ne $limit){$slider.Value=$limit}
  $d.FindName('ChargeChoice').Text=('{0:0} Вт' -f $slider.Value)
  $d.FindName('ChargeCurrent').Text=if($null -ne $limit){'Настройка станции: {0:0} Вт' -f $limit}else{'Настройка станции: —'}
  $toggle.IsChecked=($null -ne $boost -and $boost -eq 1)
  $d.FindName('XBoostCurrent').Text=if($null -eq $boost){'Состояние станции: —'}elseif($boost -eq 1){'Станция: включён'}else{'Станция: выключен'}
  $slider.IsEnabled=($ready -and $null -ne $limit)
  $d.FindName('ChargeApply').IsEnabled=($ready -and $null -ne $limit -and [int]$slider.Value -ne [int]$limit)
  $toggle.IsEnabled=($ready -and $null -ne $boost)
  $d.FindName('Connection').IsEnabled=(!$script:stationCommand)
  $d.FindName('StationControlStatus').Text=if($script:stationCommand){'Отправляю и проверяю настройку…'}
   elseif($script:stationStatus){$script:stationStatus}
   elseif(!$script:cfg){'Сначала подключи станцию EcoFlow.'}
   elseif($script:cfg.Mode -ne 'Private'){'Управление доступно при подключении через аккаунт EcoFlow.'}
   elseif($script:authBlocked){'Проверь подключение к аккаунту EcoFlow.'}
   elseif(!$fresh){'Ожидание свежих данных станции…'}
   elseif($null -eq $limit -or $null -eq $boost){'Некоторые настройки не получены от станции.'}
   elseif($script:job){'Обновляю данные станции…'}
   else{'Изменения подтверждаются станцией.'}
 }finally{$script:stationUpdating=$false}
}

function Start-StationCommand($operation,$watts,$enabled){
 if(!$script:cfg -or $script:cfg.Mode -ne 'Private' -or $script:job -or $script:authBlocked -or !$script:stationData -or !$script:lastUpdate -or ([datetime]::Now-$script:lastUpdate).TotalSeconds -ge 90){return}
 $script:stationCommand=$operation;$script:stationStatus=$null
 try{$script:job=Start-Job -ScriptBlock $worker -ArgumentList $script:cfg,$script:helperDir,$script:privateSession,$operation,$watts,$enabled}
 catch{$script:stationCommand=$null;$script:stationStatus='Не удалось запустить команду.'}
 Update-StationSettings
}

function Show-NotificationSettings {
 $d=Read-Xaml (Get-Content -LiteralPath (Join-Path $script:helperDir 'notification-settings.xaml') -Raw -Encoding UTF8)
 $d.Owner=$w
 $d.FindName('SettingsClose').Add_Click({$d.Close()})
 $d.FindName('SettingsHeader').Add_MouseLeftButtonDown({
  $node=$_.OriginalSource;while($node -and $node -ne $d){if($node -is [Windows.Controls.Primitives.ButtonBase]){return};$node=[Windows.Media.VisualTreeHelper]::GetParent($node)}
  if($_.ButtonState -eq 'Pressed'){$d.DragMove()}
 })
 $script:stationDialog=$d;$script:stationSliderDirty=$false
 $slider=$d.FindName('ChargeSlider')
 $slider.Add_ValueChanged({
  $d.FindName('ChargeChoice').Text=('{0:0} Вт' -f $slider.Value)
  if(!$script:stationUpdating){$script:stationSliderDirty=$true;Update-StationSettings}
 })
 $d.FindName('ChargeApply').Add_Click({Start-StationCommand 'SetAcChargingPower' ([int]$slider.Value) $null})
 $d.FindName('XBoost').Add_Click({$value=[bool]$d.FindName('XBoost').IsChecked;Start-StationCommand 'SetXBoost' $null $value})
 foreach($pair in @(@('AutoHigh','High'),@('AutoLow','Low'))){
  $auto=$d.FindName($pair[0]);$auto.IsChecked=[bool]$script:chargeAutomationPrefs[$pair[1]]
  $auto.Add_Click({
   $control=$_.Source;$key=[string]$control.Tag;$previous=$script:chargeAutomationPrefs[$key]
   $script:chargeAutomationPrefs[$key]=[bool]$control.IsChecked
   try{
    Save-ChargeAutomationPreferences
    $script:chargeAutomationNextAttempt=[datetime]::MinValue
    $d.FindName('AutomationStatus').Text='Сохранено. Работают, пока виджет запущен и станция в сети.'
   }catch{
    $script:chargeAutomationPrefs[$key]=$previous;$control.IsChecked=$previous
    $d.FindName('AutomationStatus').Text='Не удалось сохранить. Попробуй ещё раз.'
   }
  })
 }
 $d.Add_ContentRendered({Update-StationSettings})
 $d.Add_Closed({$script:stationDialog=$null})
 $source=[Windows.PresentationSource]::FromVisual($w)
 if($source -and $source.CompositionTarget){
  $screen=[Windows.Forms.Screen]::FromHandle(([Windows.Interop.WindowInteropHelper]::new($w)).Handle).WorkingArea
  $d.MaxHeight=$screen.Height*$source.CompositionTarget.TransformFromDevice.M22-24
 }
 foreach($key in @('LowBattery','TwoHours','FifteenMinutes','ScheduleChanges','CustomReminder')){
  $toggle=$d.FindName($key);$toggle.IsChecked=Test-NotificationEnabled $key
  $toggle.Add_Click({
   $control=$_.Source
   $script:notificationPrefs[[string]$control.Tag]=[bool]$control.IsChecked
   try{Save-NotificationPreferences;$d.FindName('SaveStatus').Text='Сохранено'}catch{$d.FindName('SaveStatus').Text='Не удалось сохранить выбор. Попробуй ещё раз.'}
   Update-OutageSummary
  })
 }
 $custom=Get-CustomLeadMinutes
 $d.FindName('CustomHours').Text=[string][int][math]::Floor($custom/60)
 $d.FindName('CustomMinutes').Text=('{0:00}' -f ($custom%60))
 $d.FindName('CustomDescription').Text='За '+(Format-LeadMinutes $custom)+' до отключения'
 $d.FindName('CustomApply').Add_Click({
  $value=ConvertTo-CustomLeadMinutes ($d.FindName('CustomHours').Text) ($d.FindName('CustomMinutes').Text)
  if($null -eq $value){$d.FindName('SaveStatus').Text='Укажи от 1 минуты до 24 часов; минуты — от 0 до 59.';return}
  $script:notificationPrefs.CustomMinutes=$value;$script:notificationPrefs.CustomReminder=$true
  try{
   Save-NotificationPreferences
   $d.FindName('CustomReminder').IsChecked=$true
   $d.FindName('CustomDescription').Text='За '+(Format-LeadMinutes $value)+' до отключения'
   $d.FindName('SaveStatus').Text='Включено: своё напоминание за '+(Format-LeadMinutes $value)
  }catch{$d.FindName('SaveStatus').Text='Не удалось сохранить время. Попробуй ещё раз.'}
  Update-OutageSummary
 })
 $d.FindName('Connection').Add_Click({Show-Settings $d})
 $d.FindName('Test').Add_Click({$script:tray.ShowBalloonTip(10000,'EcoFlow · тестовое уведомление','Уведомления Windows работают. Выбранные типы событий будут приходить автоматически.',[Windows.Forms.ToolTipIcon]::Info)})
 $d.FindName('Done').Add_Click({$d.Close()})
 $d.Add_KeyDown({if($_.Key -eq 'Escape'){$d.Close()}})
 [void]$d.ShowDialog()
}
