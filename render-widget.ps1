$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
$markup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.xaml') -Raw -Encoding UTF8
$w=[Windows.Markup.XamlReader]::Parse($markup)
$ui=@{};[xml]$xml=$markup
foreach($node in $xml.SelectNodes('//*[@Name]')){$ui[$node.Name]=$w.FindName($node.Name)}
$visual=$w.Content;$w.Content=$null
$visual.Resources=$w.Resources
[Windows.Documents.TextElement]::SetForeground($visual,$w.Foreground)
[Windows.Documents.TextElement]::SetFontFamily($visual,$w.FontFamily)
$Check=$true;$script:scheduleView='Today';$script:scheduleData=$null;$script:disableOutageNotifications=$true
. (Join-Path $PSScriptRoot 'schedule-ui.ps1')
. (Join-Path $PSScriptRoot 'load-history.ps1')
$script:loadSamples=@();$script:loadVersion=0
. (Join-Path $PSScriptRoot 'load-chart.ps1')
# A deterministic visual fixture only; never written into the real history.
$plotNow=[datetime]::UtcNow
$script:loadSamples=@(for($index=0;$index -le 90;$index++){
 $watts=82+11*[math]::Sin($index/4)
 if($index -ge 24 -and $index -le 30){$watts+=70}
 if($index -ge 58 -and $index -le 63){$watts+=38}
 if($index -ge 84){$watts=84}
 [pscustomobject]@{At=$plotNow.AddSeconds(-2700+$index*30);Watts=$watts}
})
function Save-Preview($filename,$scale=1){
 $width=$w.Width
 for($pass=0;$pass -lt 3;$pass++){
  $visual.InvalidateMeasure()
  $visual.Measure([Windows.Size]::new($width,[double]::PositiveInfinity))
  $height=[math]::Ceiling($visual.DesiredSize.Height)
  $visual.Arrange([Windows.Rect]::new(0,0,$width,$height));$visual.UpdateLayout()
 }
 Update-LoadChart $true
 $visual.UpdateLayout()
 $bmp=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]($width*$scale),[int]($height*$scale),96*$scale,96*$scale,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($visual)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
 $file=[IO.File]::Create((Join-Path $PSScriptRoot $filename));try{$encoder.Save($file)}finally{$file.Dispose()}
 $footer=if($script:activeTab -eq 'Station'){$ui.Freshness}else{$ui.ScheduleAlertsStatus}
 $bounds=$footer.TransformToAncestor($visual).TransformBounds([Windows.Rect]::new(0,0,$footer.ActualWidth,$footer.ActualHeight))
 if($bounds.Bottom -gt $height-15 -and $ui.ContentScroll.ScrollableHeight -eq 0){throw ('Footer clipped: '+$filename)}
}
$ui.Soc.Text='90 %';$ui.Charge.Value=90;$ui.Output.Text='84 Вт';$ui.Input.Text='82 Вт';$ui.Status.Text='Обновлено 10:24:18';$ui.Remaining.Text='Время работы: —'
Update-OutageSummary
Show-ScheduleTab 'Station';Save-Preview 'preview.png';Save-Preview 'station-150.png' 1.5
Show-ScheduleTab 'Schedule';Save-Preview 'schedule-preview.png'
$script:scheduleView='Latest';Render-Schedule;Save-Preview 'schedule-archive.png'
$ui.ScheduleDetails.Visibility='Visible';$ui.ScheduleDetailsToggle.Content='Свернуть';$ui.ScheduleDetailsToggle.Tag='Open';Render-Schedule;Save-Preview 'schedule-details-150.png' 1.5
# Explicit demonstration fixture, never persisted into the live schedule cache.
function Get-KyivNow {[datetime]'2026-10-18T12:30:00'}
$script:scheduleData='{"Ok":true,"cached":false,"checkedAt":"2026-10-18T12:30:00+03:00","days":[{"date":"2026-10-18","intervals":[[480,600],[900,1020],[1200,1320]],"mentioned":true,"ambiguous":false,"postId":1,"source":"https://t.me/cek_info"}],"unparsed":[]}' | ConvertFrom-Json
$script:scheduleView='Today'
$ui.Status.Text='Демонстрация · пример расписания'
$ui.Remaining.Text='Время работы: 4 ч 20 мин'
$ui.Freshness.Text='Демонстрационные интервалы · не реальный график'
Show-ScheduleTab 'Station';Update-OutageSummary;Save-Preview 'station-schedule-demo.png' 1.5
'PASS: compact station, compact schedule, details, 150% scale, footer bounds'
