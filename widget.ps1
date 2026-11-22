param([switch]$Check,[switch]$StartHidden)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'notification-preferences.ps1')
$script:notificationSettingsPath=Join-Path $PSScriptRoot 'notification-settings.json'
Read-NotificationPreferences
. (Join-Path $PSScriptRoot 'charge-automations.ps1')
$script:chargeAutomationPath=Join-Path $PSScriptRoot 'charge-automations.json'
Read-ChargeAutomationPreferences
$script:preferencesPath=Join-Path $PSScriptRoot 'preferences.json'
$script:startupLink=Join-Path ([Environment]::GetFolderPath('Startup')) 'EcoFlow Widget.lnk'
$script:lastUpdate=$null
$script:exitRequested=$false
$script:tray=$null
$script:trayIcon=$null
$script:trayValue=''
$script:alertPath=Join-Path $PSScriptRoot 'alerts.json'
$script:alertDevice=''
$script:lowChargeNotified=$false
$script:scheduleJob=$null
$script:scheduleData=$null
$script:nextSchedulePoll=[datetime]::MinValue
$script:scheduleView='Today'
$script:scheduleStarted=$true
$script:activeTab='Station'
$script:scheduleSource='https://t.me/s/cek_info'
$script:mutex=$null
$script:showSignal=$null
if(!$Check){
 $created=$false
 $script:mutex=[Threading.Mutex]::new($true,'Local\EcoFlowRiverWidget',[ref]$created)
 $signalCreated=$false
 $script:showSignal=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,'Local\EcoFlowRiverWidget.Show',[ref]$signalCreated)
 if(!$created){[void]$script:showSignal.Set();$script:mutex.Dispose();$script:showSignal.Dispose();exit}
}
$script:helperDir = $PSScriptRoot
$script:privateSession = $null
$script:stationData=$null;$script:stationCommand=$null;$script:stationStatus=$null;$script:stationDialog=$null
$script:stationSliderDirty=$false;$script:stationUpdating=$false
$script:authBlocked = $false
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Security
$script:configPath = Join-Path $PSScriptRoot 'connection.xml'
. (Join-Path $PSScriptRoot 'connection-config.ps1')
$script:cfg = if (!$Check) { Get-EcoFlowConnection $PSScriptRoot }
function Read-Xaml($s) { [Windows.Markup.XamlReader]::Parse($s) }
$w = Read-Xaml (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.xaml') -Raw -Encoding UTF8)
$ui=@{}
[xml]$widgetXml=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.xaml') -Raw -Encoding UTF8
foreach($node in $widgetXml.SelectNodes('//*[@Name]')){$ui[$node.Name]=$w.FindName($node.Name)}
$w.Add_MouseLeftButtonDown({
 $node=$_.OriginalSource
 while($node -and $node -ne $w){if($node -is [Windows.Controls.Primitives.ButtonBase] -or $node -is [Windows.Controls.TextBox]){return};$node=[Windows.Media.VisualTreeHelper]::GetParent($node)}
 if($_.ButtonState -eq 'Pressed'){$w.DragMove()}
})
$ui.Close.Add_Click({ Save-Preferences; $w.Hide() })
$ui.Pin.Add_Click({ $w.Topmost = [bool]$ui.Pin.IsChecked;Save-Preferences })
$script:job = $null; $script:nextPoll = [datetime]::MinValue
function Show-Settings {
 param($ownerWindow=$w)
 $d = Read-Xaml @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Подключение EcoFlow" Width="480" Height="570" ResizeMode="NoResize" WindowStartupLocation="CenterOwner" Background="#F3F5F8" FontFamily="Segoe UI">
<StackPanel Margin="24" Background="#F3F5F8">
<TextBlock Text="Подключение станции" FontSize="22" FontWeight="SemiBold"/>
<TextBlock Text="Используй email и пароль из приложения EcoFlow. Одобрение разработчика не нужно. Это неофициальный способ; пароль передаётся только серверу EcoFlow и сохраняется зашифрованным Windows." TextWrapping="Wrap" Margin="0,10,0,10"/>
<ComboBox Name="Mode" SelectedIndex="0" Margin="0,0,0,12"><ComboBoxItem Content="Аккаунт EcoFlow — без ожидания"/><ComboBoxItem Content="Ключи разработчика — после одобрения"/></ComboBox>
<TextBlock Text="Регион аккаунта (если вход не проходит, попробуй другой)"/><ComboBox Name="Region" SelectedIndex="0" Margin="0,4,0,10"><ComboBoxItem Content="Европа (api-e)"/><ComboBoxItem Content="Америка / другие регионы (api-a)"/><ComboBoxItem Content="Общий сервер (api.ecoflow.com)"/></ComboBox>
<TextBlock Name="AccessLabel" Text="Email аккаунта EcoFlow"/><TextBox Name="Access" Margin="0,4,0,10"/>
<TextBlock Name="SecretLabel" Text="Пароль аккаунта EcoFlow"/><PasswordBox Name="Secret" Margin="0,4,0,10"/>
<TextBlock Text="Серийный номер станции (SN из приложения)"/><TextBox Name="Serial" Margin="0,4,0,14"/>
<Button Name="Save" Content="Сохранить и подключить" Padding="10,8"/>
<TextBlock Text="SN: приложение EcoFlow → станция → настройки → информация об устройстве. Вход через Google/Apple может потребовать отдельного пароля EcoFlow." TextWrapping="Wrap" Foreground="#596579" Margin="0,12,0,0"/>
</StackPanel></Window>
'@
 $d.Owner = $ownerWindow
 $a=$d.FindName('Access'); $s=$d.FindName('Secret'); $sn=$d.FindName('Serial'); $r=$d.FindName('Region'); $mode=$d.FindName('Mode')
 $mode.Add_SelectionChanged({
  $d.FindName('AccessLabel').Text=if($mode.SelectedIndex -eq 0){'Email аккаунта EcoFlow'}else{'Access Key'}
  $d.FindName('SecretLabel').Text=if($mode.SelectedIndex -eq 0){'Пароль аккаунта EcoFlow'}else{'Secret Key'}
  $a.Clear();$s.Clear()
 })
 if ($script:cfg) {
  $mode.SelectedIndex=if($script:cfg.Mode -eq 'Private'){0}else{1}
  $a.Text=$script:cfg.Access.UserName; $s.Password=$script:cfg.Access.GetNetworkCredential().Password; $sn.Text=$script:cfg.Serial
  $r.SelectedIndex=@($script:ecoFlowHosts.Values).IndexOf([string]$script:cfg.Host)
  if($r.SelectedIndex -lt 0){$r.SelectedIndex=0}
 }
 $d.FindName('Save').Add_Click({
  if (!$a.Text.Trim() -or !$s.Password -or $sn.Text.Trim() -notmatch '^[A-Za-z0-9]+$') { [void][Windows.MessageBox]::Show('Заполни email/ключ, пароль и SN станции. SN содержит только буквы и цифры.'); return }
  $script:cfg = [pscustomobject]@{ Mode=@('Private','Public')[$mode.SelectedIndex]; Access=[pscredential]::new($a.Text.Trim(),(ConvertTo-SecureString $s.Password -AsPlainText -Force)); Serial=$sn.Text.Trim(); Host=@($script:ecoFlowHosts.Values)[$r.SelectedIndex] }
  $script:cfg | Export-Clixml $script:configPath
  Initialize-LoadHistory $script:cfg.Serial;Update-LoadChart $true
  if($script:job){ Stop-Job $script:job; Remove-Job $script:job; $script:job=$null }
  $script:privateSession=$null; $script:authBlocked=$false; $script:stationData=$null; $script:stationStatus=$null; $script:chargeAutomationNextAttempt=[datetime]::MinValue
  $script:lastUpdate=$null;$script:nextPoll=[datetime]::MinValue; $ui.Status.Text='Подключение…'; $d.Close()
 })
 [void]$d.ShowDialog()
}
. (Join-Path $PSScriptRoot 'notification-settings.ps1')
$ui.Settings.Add_Click({ Show-NotificationSettings })
$worker = {
 param($cfg,$helperDir,$privateSession,$operation,$watts,$enabled)
 try {
  if($cfg.Mode -eq 'Private'){
   $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
   if(!$python){throw 'Не найден Python. Требуется Python 3 для подключения через аккаунт.'}
   $payload=@{Host=$cfg.Host;Email=$cfg.Access.UserName;Password=$cfg.Access.GetNetworkCredential().Password;Serial=$cfg.Serial;Session=$privateSession;Operation=$operation;Watts=$watts;Enabled=$enabled} | ConvertTo-Json -Depth 8 -Compress
   $info=[Diagnostics.ProcessStartInfo]::new()
   $info.FileName=$python
   $info.Arguments='"'+(Join-Path $helperDir 'private_client.py')+'"'
   $info.UseShellExecute=$false;$info.CreateNoWindow=$true
   $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
   $info.StandardOutputEncoding=[Text.Encoding]::UTF8
   $info.EnvironmentVariables['PYTHONIOENCODING']='utf-8'
   $proc=[Diagnostics.Process]::new();$proc.StartInfo=$info
   try{
    [void]$proc.Start()
    $readOut=$proc.StandardOutput.ReadToEndAsync();$readErr=$proc.StandardError.ReadToEndAsync()
    $inputBytes=[Text.Encoding]::UTF8.GetBytes($payload+"`n")
    $proc.StandardInput.BaseStream.Write($inputBytes,0,$inputBytes.Length)
    $proc.StandardInput.BaseStream.Flush();$proc.StandardInput.BaseStream.Close();$payload=$null;$inputBytes=$null
    if(!$proc.WaitForExit(120000)){$proc.Kill();if($operation -in @('SetAcChargingPower','SetXBoost')){throw 'Результат неизвестен. Проверь настройку в приложении EcoFlow.'};throw 'Превышено время подключения к EcoFlow.'}
    $response=$readOut.Result
    if($proc.ExitCode -ne 0){throw 'Не удалось запустить подключение EcoFlow.'}
   }finally{$proc.Dispose()}
   $response | ConvertFrom-Json
   return
  }
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $access=$cfg.Access.UserName; $secret=$cfg.Access.GetNetworkCredential().Password
  function Get-Eco($path,$query) {
   $nonce=(Get-Random -Minimum 100000 -Maximum 999999).ToString()
   $ts=([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()).ToString()
   $str="accessKey=$access&nonce=$nonce&timestamp=$ts"; if($query){$str="$query&$str"}
   $h=[Security.Cryptography.HMACSHA256]::new(); $h.Key=[Text.Encoding]::UTF8.GetBytes($secret)
   try{$sig=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($str)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
   $url=$cfg.Host+'/iot-open/sign/device/'+$path; if($query){$url+='?'+$query}
   try {
    $res=Invoke-RestMethod -Uri $url -Headers @{accessKey=$access;nonce=$nonce;timestamp=$ts;sign=$sig} -TimeoutSec 12 -MaximumRedirection 0
   } catch {
    throw 'EcoFlow: ошибка запроса. Проверь интернет, регион и разрешение API.'
   }
   if([string]$res.code -ne '0'){throw 'EcoFlow отклонил запрос. Проверь регион, ключи и разрешение API.'}
   return $res.data
  }
  $devices=@(Get-Eco 'list' '')
  $device=$devices | Where-Object sn -eq $cfg.Serial | Select-Object -First 1
  if(!$device){throw 'Станция не найдена: проверь SN и регион API.'}
  if([string]$device.online -ne '1'){throw 'Станция не в сети. Проверь Wi-Fi и приложение.'}
  $data=Get-Eco 'quota/all' ('sn='+$cfg.Serial)
  [pscustomobject]@{Ok=$true;Data=$data}
 } catch { [pscustomobject]@{Ok=$false;Error=$_.Exception.Message} }
}
function Get-Metric($data,$keys) { foreach($key in $keys){$v=$data.$key;if($null -ne $v){return [double]$v}};return $null }
function Clear-Metrics { $script:stationData=$null; $script:stationStatus=$null; $ui.Soc.Text='— %';$ui.Charge.Value=0;$ui.Input.Text='— Вт';$ui.Output.Text='— Вт';$ui.Remaining.Text='Оставшееся время: —' }
function Save-AlertState {
 try{@{DeviceHash=$script:alertDevice;Notified=$script:lowChargeNotified} | ConvertTo-Json | Set-Content -LiteralPath $script:alertPath -Encoding UTF8}catch{}
}
function Show-LowChargeNotification($soc){
 if(!$script:tray){return}
 $script:tray.ShowBalloonTip(10000,'EcoFlow: низкий заряд',('Осталось {0:0.#}%. Подключи станцию к зарядке.' -f $soc),[Windows.Forms.ToolTipIcon]::Warning)
}
function Update-LowChargeAlert($soc){
 if($null -eq $soc -or [double]::IsNaN($soc) -or [double]::IsInfinity($soc) -or $soc -lt 0 -or $soc -gt 100){return}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$device=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$script:cfg.Serial)))).Replace('-','')}finally{$sha.Dispose()}
 if($script:alertDevice -ne $device){
  $script:alertDevice=$device;$script:lowChargeNotified=$false
  if(Test-Path -LiteralPath $script:alertPath){try{
   $state=Get-Content -LiteralPath $script:alertPath -Raw | ConvertFrom-Json
   if($state.DeviceHash -eq $device){$script:lowChargeNotified=($state.Notified -eq $true)}
  }catch{}}
 }
 if($soc -ge 25 -and $script:lowChargeNotified){$script:lowChargeNotified=$false;Save-AlertState}
 elseif($soc -lt 20 -and !$script:lowChargeNotified -and (Test-NotificationEnabled 'LowBattery')){
  Show-LowChargeNotification $soc
  $script:lowChargeNotified=$true;Save-AlertState
 }
}
function Save-Preferences {
 if($Check){return}
 try{@{Left=$w.Left;Top=$w.Top;Pinned=[bool]$ui.Pin.IsChecked} | ConvertTo-Json | Set-Content -LiteralPath $script:preferencesPath -Encoding UTF8}catch{}
}
function Show-Widget {
 $w.Show();$w.WindowState='Normal';[void]$w.Activate()
}
function Request-Refresh {
 if(!$script:cfg){Show-Widget;Show-Settings;return}
 if($script:authBlocked){Show-Widget;Show-Settings;return}
 $script:nextPoll=[datetime]::MinValue
 if(!$script:job){$ui.Status.Text='Обновление…'}
}
function Set-TrayValue($value,$description){
 if(!$script:tray){return}
 $script:tray.Text=$description.Substring(0,[Math]::Min(63,$description.Length))
 if($script:trayValue -eq $value){return}
 $script:trayValue=$value
 $bitmap=[Drawing.Bitmap]::new(32,32);$graphics=[Drawing.Graphics]::FromImage($bitmap)
 $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
 $graphics.Clear([Drawing.Color]::Transparent)
 $brush=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#7CE9C2'))
 if($value -eq '--'){$brush.Color=[Drawing.ColorTranslator]::FromHtml('#9BAABD')}
 elseif([int]$value -le 20){$brush.Color=[Drawing.ColorTranslator]::FromHtml('#FFAF70')}
 $font=[Drawing.Font]::new('Segoe UI',15,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
 $format=[Drawing.StringFormat]::new();$format.Alignment='Center';$format.LineAlignment='Center'
 $graphics.FillRectangle($brush,3,26,26,3)
 $graphics.DrawString($value,$font,$brush,[Drawing.RectangleF]::new(0,0,32,25),$format)
 $handle=$bitmap.GetHicon()
 try{$newIcon=([Drawing.Icon]::FromHandle($handle)).Clone()}finally{[void][RiverIconNative]::DestroyIcon($handle);$font.Dispose();$brush.Dispose();$graphics.Dispose();$format.Dispose();$bitmap.Dispose()}
 $old=$script:trayIcon;$script:trayIcon=$newIcon;$script:tray.Icon=$newIcon;if($old){$old.Dispose()}
}
if(!$Check){
 Add-Type 'using System;using System.Runtime.InteropServices;public static class RiverIconNative{[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);}'
 if(Test-Path $script:preferencesPath){try{
  $preferences=Get-Content -LiteralPath $script:preferencesPath -Raw | ConvertFrom-Json
  $ui.Pin.IsChecked=[bool]$preferences.Pinned;$w.Topmost=[bool]$preferences.Pinned
  $desktop=[Windows.Forms.SystemInformation]::VirtualScreen
  $w.WindowStartupLocation='Manual'
  $w.Left=[double]$preferences.Left
  $w.Top=[double]$preferences.Top
 }catch{}}
 $script:tray=[Windows.Forms.NotifyIcon]::new()
 $menu=[Windows.Forms.ContextMenuStrip]::new()
 $item=$menu.Items.Add('Открыть / скрыть виджет');$item.Add_Click({if($w.IsVisible){Save-Preferences;$w.Hide()}else{Show-Widget}})
 $item=$menu.Items.Add('Обновить сейчас');$item.Add_Click({Request-Refresh})
 $item=$menu.Items.Add('Проверить уведомления');$item.Add_Click({$script:tray.ShowBalloonTip(10000,'EcoFlow · тестовое уведомление','Показ уведомлений работает. Выбор событий доступен в настройках виджета.',[Windows.Forms.ToolTipIcon]::Info)})
 [void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
 $item=$menu.Items.Add('Выйти');$item.Add_Click({$script:exitRequested=$true;$w.Close()})
 $script:tray.ContextMenuStrip=$menu
 $script:tray.Add_BalloonTipClicked({Show-Widget})
 $script:tray.Add_MouseClick({if($_.Button -eq [Windows.Forms.MouseButtons]::Left){if($w.IsVisible){Save-Preferences;$w.Hide()}else{Show-Widget}}})
 Set-TrayValue '--' 'EcoFlow · подключение…'
 $script:tray.Visible=$true
}
$ui.Refresh.Add_Click({Request-Refresh})
. (Join-Path $PSScriptRoot 'schedule-ui.ps1')
. (Join-Path $PSScriptRoot 'load-history.ps1')
$script:loadHistoryPath=Join-Path $PSScriptRoot 'load-history.json'
Initialize-LoadHistory $script:cfg.Serial
. (Join-Path $PSScriptRoot 'load-chart.ps1')
$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[timespan]::FromSeconds(1)
$timer.Add_Tick({
 Update-LoadChart
 Update-OutageSummary
 Update-ScheduleJob
 if($script:showSignal -and $script:showSignal.WaitOne(0)){Show-Widget}
 $ui.Refresh.IsEnabled=($null -eq $script:job)
 Update-StationSettings
 if($script:lastUpdate){$age=[int]([datetime]::Now-$script:lastUpdate).TotalSeconds;$ui.Freshness.Text="Получено $age с назад · авто 30 с"}
 if($script:job -and $script:job.State -in @('Completed','Failed','Stopped')){
  $wasStationCommand=$script:stationCommand;$script:stationCommand=$null
  $result=Receive-Job $script:job -ErrorAction SilentlyContinue; Remove-Job $script:job; $script:job=$null
  if($wasStationCommand -and (!$result -or !$result.Ok)){
   $script:stationStatus=if($result.Error){$result.Error}else{'Результат неизвестен. Проверь приложение EcoFlow.'}
   $script:stationData=$null
   $script:nextPoll=[datetime]::Now.AddSeconds(30)
   if($result.Session){$script:privateSession=$result.Session}
   if($result.AuthFailed){$script:authBlocked=$true;$script:privateSession=$null}
   Update-StationSettings
   return
  }
  $script:nextPoll=[datetime]::Now.AddSeconds(30)
  if($result.Session){$script:privateSession=$result.Session}
  if($result.AuthFailed){$script:authBlocked=$true;$script:privateSession=$null}
  if($result -and $result.Ok){
   $data=$result.Data
   $script:stationData=$data
   if($wasStationCommand){$script:stationStatus='Станция подтвердила изменение.';$script:stationSliderDirty=$false}else{$script:stationStatus=$null}
   $soc=Get-Metric $data @('bms_emsStatus.lcdShowSoc','pd.soc','bms_bmsStatus.soc')
   $inW=Get-Metric $data @('pd.wattsInSum');$outW=Get-Metric $data @('pd.wattsOutSum')
   if($null -eq $soc){Clear-Metrics;$ui.Status.Text='API ответил без данных о заряде';return}
   $ui.Soc.Text=('{0:0} %' -f $soc);$ui.Charge.Value=[Math]::Max(0,[Math]::Min(100,$soc))
   $ui.Input.Text=if($null -ne $inW){'{0:0} Вт' -f $inW}else{'— Вт'}
   $ui.Output.Text=if($null -ne $outW){'{0:0} Вт' -f $outW}else{'— Вт'}
   if($null -ne $outW){Add-LoadSample $outW ([datetime]::UtcNow) $script:cfg.Serial;Update-LoadChart $true}
   $keys=if($inW -gt $outW){@('bms_emsStatus.chgRemainTime','pd.remainTime')}else{@('bms_emsStatus.dsgRemainTime','pd.remainTime')}
   $mins=Get-Metric $data $keys
   $ui.Remaining.Text=if($null -ne $mins -and $mins -gt 0 -and $mins -lt 5999){'Осталось: {0} ч {1:00} мин' -f [math]::Floor($mins/60),($mins%60)}else{'Оставшееся время: —'}
   $ui.Status.Text='Обновлено '+[datetime]::Now.ToString('HH:mm:ss')
   $script:lastUpdate=[datetime]::Now
   $trayTime=if($null -ne $mins -and $mins -gt 0 -and $mins -lt 5999){'{0} ч {1:00} мин' -f [math]::Floor($mins/60),($mins%60)}else{'—'}
   Set-TrayValue ('{0:0}' -f $soc) ('EcoFlow · {0:0}% · осталось {1} · выход {2:0} Вт' -f $soc,$trayTime,$outW)
   Update-LowChargeAlert $soc
  }else{Clear-Metrics;$ui.Status.Text=if($result){$result.Error}else{'Не удалось получить данные'};$ui.Status.ToolTip=$ui.Status.Text;$script:lastUpdate=$null;$ui.Freshness.Text='Нет свежих данных';Set-TrayValue '--' 'EcoFlow · нет свежих данных'}
 }
 Update-StationSettings
 if($script:cfg -and !$script:authBlocked -and !$script:job -and [datetime]::Now -ge $script:nextPoll){$script:job=Start-Job -ScriptBlock $worker -ArgumentList $script:cfg,$script:helperDir,$script:privateSession}
 if(!$script:job){Update-ChargeAutomations}
})
$w.Add_Closing({if(!$script:exitRequested){$_.Cancel=$true;Save-Preferences;$w.Hide()}})
$w.Add_Closed({Save-Preferences;$timer.Stop();if($script:scheduleJob){Stop-Job $script:scheduleJob;Remove-Job $script:scheduleJob};if($script:job){Stop-Job $script:job;Remove-Job $script:job};if($script:tray){$script:tray.Visible=$false;$script:tray.Dispose()};if($script:trayIcon){$script:trayIcon.Dispose()};if($script:mutex){$script:mutex.ReleaseMutex();$script:mutex.Dispose()};if($script:showSignal){$script:showSignal.Dispose()};if($script:application){$script:application.Shutdown()}})
if($Check){ & (Join-Path $PSScriptRoot 'render-widget.ps1'); 'WPF and XAML OK'; exit }
$w.Add_ContentRendered({if(!$script:openedSettings){$script:openedSettings=$true;if(!$script:cfg){Show-Settings}elseif($StartHidden){$w.Hide()}}})
$timer.Start()
$script:application=[Windows.Application]::new()
$script:application.ShutdownMode=[Windows.ShutdownMode]::OnExplicitShutdown
[void]$script:application.Run($w)
