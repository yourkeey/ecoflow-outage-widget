function Draw-LoadPlot($canvas,$now,$large=$false){
 $canvas.Children.Clear()
 $width=$canvas.ActualWidth;if($width -le 0){$width=if($large){260}else{80}}
 $height=$canvas.Height
 $plot=Get-LoadPlot $script:loadSamples $now $width $height
 $line=[Windows.Shapes.Line]::new();$line.X1=2;$line.X2=$width-2;$line.Y1=$height-2;$line.Y2=$height-2;$line.Stroke='#6D7A96';$line.StrokeThickness=1;[void]$canvas.Children.Add($line)
 if($large){
  $grid=[Windows.Shapes.Line]::new();$grid.X1=2;$grid.X2=$width-2;$grid.Y1=$height/2;$grid.Y2=$height/2;$grid.Stroke='#52617E';$grid.StrokeThickness=1;$grid.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@(2,4));[void]$canvas.Children.Add($grid)
 }
 foreach($group in $plot.Groups){
  if($group.Count -ge 2){
   $figure=[Windows.Media.PathFigure]::new();$figure.StartPoint=[Windows.Point]::new($group[0].X,$group[0].Y)
   $segments=[Windows.Media.PolyLineSegment]::new()
   foreach($point in $group | Select-Object -Skip 1){$segments.Points.Add([Windows.Point]::new($point.X,$point.Y))}
   $figure.Segments.Add($segments)
   $geometry=[Windows.Media.PathGeometry]::new();$geometry.Figures.Add($figure)
   $path=[Windows.Shapes.Path]::new();$path.Data=$geometry;$path.Stroke='#79DDBB';$path.StrokeThickness=if($large){1.8}else{1.5};$path.StrokeLineJoin='Round';$path.StrokeStartLineCap='Round';$path.StrokeEndLineCap='Round'
   $fillFigure=$figure.Clone();$fillFigure.IsClosed=$true
   $fillFigure.Segments.Add([Windows.Media.LineSegment]::new([Windows.Point]::new($group[-1].X,$height-2),$true))
   $fillFigure.Segments.Add([Windows.Media.LineSegment]::new([Windows.Point]::new($group[0].X,$height-2),$true))
   $fillGeometry=[Windows.Media.PathGeometry]::new();$fillGeometry.Figures.Add($fillFigure)
   $brush=[Windows.Media.LinearGradientBrush]::new();$brush.StartPoint=[Windows.Point]::new(0,0);$brush.EndPoint=[Windows.Point]::new(0,1)
   $brush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString('#3379DDBB'),0))
   $brush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString('#0079DDBB'),1))
   $fill=[Windows.Shapes.Path]::new();$fill.Data=$fillGeometry;$fill.Fill=$brush;[void]$canvas.Children.Add($fill);[void]$canvas.Children.Add($path)
  }
 }
 if($plot.Samples.Count){
  $last=$plot.Groups[$plot.Groups.Count-1];$point=$last[$last.Count-1]
  $dot=[Windows.Shapes.Ellipse]::new();$dot.Width=4;$dot.Height=4;$dot.Fill=if(($now.ToUniversalTime()-$point.Sample.At).TotalSeconds -le 90){'#B0F1D9'}else{'#718797'}
  [Windows.Controls.Canvas]::SetLeft($dot,$point.X-2);[Windows.Controls.Canvas]::SetTop($dot,$point.Y-2);[void]$canvas.Children.Add($dot)
 }
 return $plot
}
function Draw-LoadDetails {
 $now=[datetime]::UtcNow
 $plot=Draw-LoadPlot ($script:loadTip.FindName('Plot')) $now $true
 $script:loadTip.FindName('Scale').Text=('{0:0} Вт' -f $plot.Top)
 if($plot.Samples.Count){
  $stats=$plot.Samples | Measure-Object Watts -Minimum -Maximum
  $script:loadTip.FindName('Stats').Text=('Мин. {0:0} Вт  ·  пик {1:0} Вт' -f $stats.Minimum,$stats.Maximum)
  $script:loadTip.FindName('Reading').Text='Нагрузка за последние 45 минут'
 }else{
  $script:loadTip.FindName('Stats').Text='История начнёт появляться с новых измерений'
  $script:loadTip.FindName('Reading').Text='Ожидаю данные станции'
 }
}
function Update-LoadChart($force=$false){
 $now=[datetime]::UtcNow
 if(!$force -and $script:loadChartNext -and $now -lt $script:loadChartNext){return}
 $script:loadChartNext=$now.AddSeconds(15)
 $plot=Draw-LoadPlot $ui.LoadChart $now
 $ui.LoadChartCaption.Text=if($plot.Samples.Count){'45 мин'}else{'история'}
 if($script:loadTip.IsOpen){Draw-LoadDetails}
}
$script:loadTip=[Windows.Markup.XamlReader]::Parse(@'
<ToolTip xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Background="#303B58" Foreground="#E5F1F5" BorderBrush="#8799BA" BorderThickness="1" Padding="13" Placement="Bottom">
 <StackPanel Width="260">
  <Grid Margin="0,0,0,10"><TextBlock Text="НАГРУЗКА · 45 МИН" FontFamily="Segoe UI" FontSize="10" Foreground="#91B3BC"/><TextBlock Name="Scale" HorizontalAlignment="Right" FontSize="10" Foreground="#A7B4CE"/></Grid>
  <Canvas Name="Plot" Width="260" Height="88" ClipToBounds="True"/>
  <DockPanel Margin="0,5,0,10"><TextBlock Text="−45 мин" FontSize="9" Foreground="#A7B4CE"/><TextBlock Text="сейчас" FontSize="9" Foreground="#A7B4CE" HorizontalAlignment="Right"/></DockPanel>
  <TextBlock Name="Reading" Text="" FontFamily="Segoe UI" FontSize="11" Margin="0,0,0,4"/>
  <TextBlock Name="Stats" Text="" FontFamily="Segoe UI" FontSize="10" Foreground="#A7B4CE"/>
 </StackPanel>
</ToolTip>
'@)
$ui.LoadChartHost.ToolTip=$script:loadTip
$script:loadTip.Add_Opened({Draw-LoadDetails})
$ui.LoadChart.Add_SizeChanged({Update-LoadChart $true})
$ui.LoadChartHost.Add_MouseMove({
 if(!$script:loadSamples.Count){return}
 $width=$ui.LoadChart.ActualWidth;if($width -le 0){return}
 $x=$_.GetPosition($ui.LoadChart).X
 $target=[datetime]::UtcNow.AddMinutes(-45).AddSeconds(2700*[math]::Max(0,[math]::Min(1,$x/$width)))
 $from=[datetime]::UtcNow.AddMinutes(-45)
 $closest=$script:loadSamples | Where-Object At -ge $from | Sort-Object @{Expression={[math]::Abs(($_.At-$target).TotalSeconds)}} | Select-Object -First 1
 if($closest -and [math]::Abs(($closest.At-$target).TotalSeconds) -le 90){
  $clock=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($closest.At,'FLE Standard Time').ToString('HH:mm:ss')
  $script:loadTip.FindName('Reading').Text=('{0}  ·  {1:0} Вт' -f $clock,$closest.Watts)
 }else{$script:loadTip.FindName('Reading').Text='В этот момент нет измерения'}
})
Update-LoadChart $true
