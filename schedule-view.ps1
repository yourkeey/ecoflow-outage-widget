function Update-WidgetLayout {
 $w.SizeToContent='Height'
 $w.Width=360
 if(!$Check -and $w.IsLoaded){
  $source=[Windows.PresentationSource]::FromVisual($w)
  if($source -and $source.CompositionTarget){
   $transform=$source.CompositionTarget.TransformFromDevice
   $screen=[Windows.Forms.Screen]::FromHandle(([Windows.Interop.WindowInteropHelper]::new($w)).Handle).WorkingArea
   $top=$screen.Top*$transform.M22;$left=$screen.Left*$transform.M11
   $height=$screen.Height*$transform.M22;$width=$screen.Width*$transform.M11
   $ui.ContentScroll.MaxHeight=[math]::Max(150,$height-160)
   $w.UpdateLayout()
   $w.Top=[math]::Max($top,[math]::Min($w.Top,$top+$height-$w.ActualHeight-8))
   $w.Left=[math]::Max($left,[math]::Min($w.Left,$left+$width-$w.ActualWidth))
  }
 }
}
function Show-ScheduleTab($tab){
 $script:activeTab=$tab
 $ui.StationPanel.Visibility=if($tab -eq 'Station'){'Visible'}else{'Collapsed'}
 $ui.SchedulePanel.Visibility=if($tab -eq 'Schedule'){'Visible'}else{'Collapsed'}
 foreach($pair in @(@('TabStation','Station'),@('TabSchedule','Schedule'))){
  $ui[$pair[0]].Background=if($tab -eq $pair[1]){'#A0607C89'}else{'Transparent'}
  $ui[$pair[0]].Foreground=if($tab -eq $pair[1]){'#89EDCA'}else{'#C0CAE0'}
 }
 if($tab -eq 'Schedule'){Render-Schedule}
 Update-WidgetLayout
}
function Update-StationIntervals($data,$now,$context){
 $day=$context.Today
 if(!$day -or !$day.mentioned -or $day.ambiguous -or @($day.intervals).Count -eq 0){$day=if($context.Event){$context.Event.Day}else{$null}}
 if(!$day -or !$day.mentioned -or $day.ambiguous -or @($day.intervals).Count -eq 0){
  $ui.StationIntervalsSection.Visibility='Collapsed';$ui.StationIntervals.Children.Clear();$ui.StationIntervalsAxis.Children.Clear();$script:stationIntervalsKey='';return
 }
 $date=[datetime]::ParseExact($day.date,'yyyy-MM-dd',$null)
 if($date -lt $now.Date){$ui.StationIntervalsSection.Visibility='Collapsed';return}
 $width=290;if($ui.StationIntervals.ActualWidth -gt 0){$width=$ui.StationIntervals.ActualWidth}
 $key=$day.date+'|'+$width+'|'+$now.ToString('HH:mm')+'|'+(@(foreach($range in $day.intervals){[string]$range[0]+'-'+[string]$range[1]}) -join ',')
 $ui.StationIntervalsSection.Visibility='Visible'
 if($script:stationIntervalsKey -eq $key){return}
 $script:stationIntervalsKey=$key
 $ui.StationIntervalsDate.Text=if($date -eq $now.Date){'СЕГОДНЯ · ПЛАНОВЫЕ ОТКЛЮЧЕНИЯ'}else{'ЗАВТРА · ПЛАНОВЫЕ ОТКЛЮЧЕНИЯ'}
 $ui.StationIntervals.Children.Clear()
 $ui.StationIntervalsAxis.Children.Clear()
 for($index=0;$index -le 4;$index++){
  $label=[Windows.Controls.TextBlock]::new();$label.Text=('{0:00}' -f ($index*6));$label.FontSize=9;$label.Foreground='#A7B4CE'
  [Windows.Controls.Canvas]::SetLeft($label,[math]::Max(0,[math]::Min($width-11,$width*$index/4-5)));[void]$ui.StationIntervalsAxis.Children.Add($label)
 }
 foreach($range in $day.intervals){
  $start=$date.AddMinutes([int]$range[0]);$end=$date.AddMinutes([int]$range[1])
  $past=$end -le $now;$active=$start -le $now -and !$past
  $block=[Windows.Shapes.Rectangle]::new();$block.Tag='OutageInterval';$block.Width=$width*([int]$range[1]-[int]$range[0])/1440;$block.Height=18;$block.RadiusX=3;$block.RadiusY=3
  $block.Fill=if($active){'#F0BC8F'}elseif($past){'#846A55'}else{'#DDA175'}
  $block.ToolTip=(Format-ScheduleMinute $range[0])+' — '+(Format-ScheduleMinute $range[1])
  [Windows.Controls.Canvas]::SetLeft($block,$width*[int]$range[0]/1440);[void]$ui.StationIntervals.Children.Add($block)
 }
 if($date -eq $now.Date){
  $marker=[Windows.Shapes.Rectangle]::new();$marker.Tag='Now';$marker.Width=2;$marker.Height=18;$marker.Fill='#E7F4EF';$marker.ToolTip='Сейчас · '+$now.ToString('HH:mm')
  [Windows.Controls.Canvas]::SetLeft($marker,[math]::Min($width-2,$width*($now.Hour*60+$now.Minute)/1440));[void]$ui.StationIntervals.Children.Add($marker)
 }
}
function Update-OutageSummary {
 $now=Get-KyivNow
 $context=Get-OutageContext $script:scheduleData $now
 $event=$context.Event
 $ui.OutageLabel.Text='ГРАФИК · ЧЕРГА 2.2'
 $ui.OutageCard.Background='#66455272';$ui.OutageCard.BorderBrush='#887C91B8'
 if($context.Current){
  $ui.OutageLabel.Text='ДО ВКЛЮЧЕНИЯ ПО ГРАФИКУ'
  $ui.OutageCountdown.Text=Format-OutageCountdown ($event.End-$now)
  $ui.OutageHint.Text='Отключение '+$event.Range+' · до '+$event.End.ToString('HH:mm')
  $ui.OutageCard.Background='#87584F59';$ui.OutageCard.BorderBrush='#A39C8C85'
 }elseif($context.Next){
  $ui.OutageLabel.Text='ДО ОТКЛЮЧЕНИЯ ПО ГРАФИКУ'
  $ui.OutageCountdown.Text=Format-OutageCountdown ($event.Start-$now)
  $day=if($event.Start.Date -eq $now.Date){'Сегодня'}else{'Завтра'}
  $ui.OutageHint.Text=$day+' · '+$event.Range+' · черга 2.2'
 }elseif(!$script:scheduleData){
  $ui.OutageCountdown.Text='Проверяю график…';$ui.OutageHint.Text='Публикации ЦЕК · время Киев'
 }elseif(!$context.Today -or !$context.Today.mentioned -or $context.Today.ambiguous){
  $ui.OutageCountdown.Text='Нет графика на сегодня';$ui.OutageHint.Text='Ждём подтверждённое расписание ЦЕК'
 }else{
  $ui.OutageCountdown.Text='Новых интервалов нет';$ui.OutageHint.Text='Все опубликованные интервалы на сегодня прошли'
 }
 if($event -and !$context.Trusted){$ui.OutageHint.Text+=' · требует проверки'}
 $reminders=(Test-NotificationEnabled 'TwoHours') -or (Test-NotificationEnabled 'FifteenMinutes') -or (Test-NotificationEnabled 'CustomReminder')
 $ui.ReminderPreferencesSummary.Text=Get-ReminderSummary
 $ui.LowBatteryPreferencesSummary.Text=if(Test-NotificationEnabled 'LowBattery'){'Заряд ниже 20%'}else{'Низкий заряд: выкл.'}
 $ui.ScheduleAlertsStatus.Text=if(!$reminders){'Напоминания до отключения выключены'}elseif($event -and !$context.Trusted){'Напоминания: пауза до проверки свежего графика'}elseif(!$event){'Напоминания '+(Get-ReminderSummary)+' · ждём график'}else{'Напоминания '+(Get-ReminderSummary)}
 Update-StationIntervals $script:scheduleData $now $context
 if(!$script:disableOutageNotifications){Update-OutageNotifications $script:scheduleData $now}
}
function Render-Schedule {
 $now=Get-KyivNow;$today=$now.ToString('yyyy-MM-dd')
 $requested=if($script:scheduleView -eq 'Tomorrow'){$now.AddDays(1).ToString('yyyy-MM-dd')}else{$today}
 foreach($pair in @(@('DayToday','Today'),@('DayTomorrow','Tomorrow'),@('DayLatest','Latest'))){
  $ui[$pair[0]].Background=if($script:scheduleView -eq $pair[1]){'#A0607C89'}else{'#59475476'}
  $ui[$pair[0]].Foreground=if($script:scheduleView -eq $pair[1]){'#89EDCA'}else{'#C2CBE1'}
 }
 $ui.ScheduleIntervals.Children.Clear();$ui.ScheduleTimeline.Children.Clear();$ui.ScheduleAxis.Children.Clear()
 $days=if($script:scheduleData -and $script:scheduleData.Ok){@($script:scheduleData.days | Sort-Object date -Descending)}else{@()}
 $selected=if($script:scheduleView -eq 'Latest'){$days | Select-Object -First 1}else{$days | Where-Object date -eq $requested | Select-Object -First 1}
 $date=if($selected){$selected.date}else{$requested}
 $ru=[Globalization.CultureInfo]::GetCultureInfo('ru-RU')
 $ui.ScheduleDate.Text=([datetime]::ParseExact($date,'yyyy-MM-dd',$null)).ToString('d MMMM',$ru)
 $script:scheduleSource=if($selected){$selected.source}else{'https://t.me/s/cek_info'}
 $ui.ScheduleNotice.Text=if(!$script:scheduleData){'Проверяю публикации канала…'}elseif(!$script:scheduleData.Ok){$script:scheduleData.error}elseif(!$selected){'Расписание на эту дату ещё не найдено.'}elseif($selected.date -lt $today){'Архивная публикация · это не график на сегодня.'}elseif($selected.ambiguous){'Нужна проверка: публикация разобрана не полностью.'}elseif(!$selected.mentioned){'В этой публикации черга 2.2 не указана.'}else{'По публикации ЦЕК · время Киев'}
 $ranges=@();if($selected){$ranges=@($selected.intervals)}
 $total=0;$width=318
 if($ui.ScheduleTimeline.ActualWidth -gt 0){$width=$ui.ScheduleTimeline.ActualWidth}
 for($i=0;$i -le 4;$i++){
  $label=[Windows.Controls.TextBlock]::new();$label.Text=('{0:00}' -f ($i*6));$label.FontSize=9;$label.Foreground='#A7B4CE'
  [Windows.Controls.Canvas]::SetLeft($label,[math]::Max(0,[math]::Min($width-11,$width*$i/4-5)));[void]$ui.ScheduleAxis.Children.Add($label)
 }
 foreach($range in $ranges){
  $start=[int]$range[0];$end=[int]$range[1];$total+=($end-$start)
  $block=[Windows.Shapes.Rectangle]::new();$block.Width=$width*($end-$start)/1440;$block.Height=18;$block.RadiusX=4;$block.RadiusY=4;$block.Fill='#DDA175'
  $block.ToolTip=(Format-ScheduleMinute $start)+' — '+(Format-ScheduleMinute $end)
  [Windows.Controls.Canvas]::SetLeft($block,$width*$start/1440);[void]$ui.ScheduleTimeline.Children.Add($block)
  $card=[Windows.Controls.Border]::new();$card.Background='#66505B79';$card.CornerRadius=[Windows.CornerRadius]::new(9);$card.Padding=[Windows.Thickness]::new(11,8,11,8);$card.Margin=[Windows.Thickness]::new(0,0,0,5)
  $row=[Windows.Controls.Grid]::new();$column=[Windows.Controls.ColumnDefinition]::new();$row.ColumnDefinitions.Add($column);$column=[Windows.Controls.ColumnDefinition]::new();$column.Width=[Windows.GridLength]::Auto;$row.ColumnDefinitions.Add($column)
  $text=[Windows.Controls.TextBlock]::new();$text.Text=(Format-ScheduleMinute $start)+' — '+(Format-ScheduleMinute $end);$text.Foreground='#F0C29F';$text.FontSize=14;$text.FontWeight='SemiBold'
  $duration=[Windows.Controls.TextBlock]::new();$duration.Text=('{0} ч {1:00} м' -f [math]::Floor(($end-$start)/60),(($end-$start)%60));$duration.Foreground='#ACBDD2';$duration.FontSize=10;$duration.VerticalAlignment='Center';[Windows.Controls.Grid]::SetColumn($duration,1)
  [void]$row.Children.Add($text);[void]$row.Children.Add($duration);$card.Child=$row;[void]$ui.ScheduleIntervals.Children.Add($card)
 }
 if($ranges.Count -gt 0 -and $date -eq $today){
  $marker=[Windows.Shapes.Rectangle]::new();$marker.Width=2;$marker.Height=18;$marker.Fill='#E7F4EF';$marker.ToolTip='Сейчас · '+$now.ToString('HH:mm')
  [Windows.Controls.Canvas]::SetLeft($marker,[math]::Min($width-2,$width*($now.Hour*60+$now.Minute)/1440));[void]$ui.ScheduleTimeline.Children.Add($marker)
 }
 $focus=$null
 if($ranges.Count -gt 0){
  $minute=if($date -eq $today){$now.Hour*60+$now.Minute}else{0}
  foreach($range in $ranges){if([int]$range[1] -gt $minute){$focus=$range;break}}
  if(!$focus){$focus=$ranges[$ranges.Count-1]}
 }
 if($focus){
  $ui.ScheduleCompactLabel.Text=if($date -lt $today){'ПОСЛЕДНЯЯ ПУБЛИКАЦИЯ'}elseif($date -eq $today -and [int]$focus[0] -le ($now.Hour*60+$now.Minute) -and [int]$focus[1] -gt ($now.Hour*60+$now.Minute)){'ОТКЛЮЧЕНИЕ ПО ГРАФИКУ'}else{'ИНТЕРВАЛ ПО ГРАФИКУ'}
  $ui.ScheduleCompactValue.Text=(Format-ScheduleMinute $focus[0])+' — '+(Format-ScheduleMinute $focus[1])
  $ui.ScheduleSummary.Text=('Всего: {0} ч {1:00} мин' -f [math]::Floor($total/60),($total%60))+$(if($ranges.Count -gt 1){' · интервалов '+$ranges.Count}else{''})
 }else{
  $ui.ScheduleCompactLabel.Text='ЧЕРГА 2.2'
  $ui.ScheduleCompactValue.Text=if($script:scheduleData){'Ожидаем расписание'}else{'Проверяю график…'}
  $last=$days | Select-Object -First 1
  $ui.ScheduleSummary.Text=if($last){'Последняя публикация: '+([datetime]$last.date).ToString('dd.MM')+'. Смотри «Последний».'}else{'Нет подтверждённых интервалов.'}
 }
 if(!$ranges.Count){$empty=[Windows.Controls.TextBlock]::new();$empty.Text='Интервалы на эту дату не опубликованы.';$empty.FontSize=11;$empty.Foreground='#A7B4CE';[void]$ui.ScheduleIntervals.Children.Add($empty)}
 $ui.ScheduleMeta.Text=''
 if($script:scheduleData -and $script:scheduleData.checkedAt){
  $checked=[DateTimeOffset]::Parse($script:scheduleData.checkedAt)
  $ui.ScheduleMeta.Text=if($script:scheduleData.cached){'Копия от '+$checked.ToString('dd.MM HH:mm')+' · проверяю актуальность'}else{'Проверено '+$checked.ToString('dd.MM HH:mm')+' · авто 5 мин'}
  if($script:scheduleData.error){$ui.ScheduleMeta.Text+="`nНет связи с Telegram. Показаны сохранённые данные."}
  if($selected -and @($script:scheduleData.unparsed | Where-Object postId -gt $selected.postId).Count -gt 0){$ui.ScheduleMeta.Text+="`nЕсть более свежий нераспознанный пост. Проверь канал."}
 }
 Update-OutageSummary
 Update-WidgetLayout
}
