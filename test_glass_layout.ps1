$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
$markup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'notification-settings.xaml') -Raw -Encoding UTF8
$w=[Windows.Markup.XamlReader]::Parse($markup)
$w.FindName('ChargeSlider').Value=500;$w.FindName('ChargeSlider').IsEnabled=$true
$w.FindName('ChargeChoice').Text='500 Вт';$w.FindName('ChargeCurrent').Text='Настройка станции: 500 Вт'
$w.FindName('ChargeApply').IsEnabled=$true;$w.FindName('XBoost').IsEnabled=$true;$w.FindName('XBoost').IsChecked=$true
$w.FindName('XBoostCurrent').Text='Станция: включён';$w.FindName('AutoHigh').IsChecked=$true
$visual=$w.Content;$w.Content=$null;$visual.Resources=$w.Resources
[Windows.Documents.TextElement]::SetForeground($visual,$w.Foreground)
[Windows.Documents.TextElement]::SetFontFamily($visual,$w.FontFamily)
$hostVisual=[Windows.Controls.Border]::new();$hostVisual.Width=400;$hostVisual.Height=850;$hostVisual.Background=$w.Background;$hostVisual.Child=$visual
$hostVisual.Measure([Windows.Size]::new(400,850));$hostVisual.Arrange([Windows.Rect]::new(0,0,400,850));$hostVisual.UpdateLayout()
$track=$w.FindName('ChargeSlider').Template.FindName('PART_Track',$w.FindName('ChargeSlider'))
if(!$track -or !$track.Thumb){throw 'Slider track not rendered'}
$scroll=$w.FindName('SettingsScroll')
$bar=$scroll.Template.FindName('PART_VerticalScrollBar',$scroll)
if(!$bar -or $scroll.ScrollableHeight -le 0){throw 'Settings scroll bar missing'}
$scroll.ScrollToVerticalOffset(150);$hostVisual.UpdateLayout()
if($scroll.VerticalOffset -lt 100 -or $bar.Value -lt 100){throw 'Scrolling did not update custom track'}
$scrollTrack=$bar.Template.FindName('PART_Track',$bar)
$thumb=$scrollTrack.Thumb
$before=$scroll.VerticalOffset
$start=[Windows.Controls.Primitives.DragStartedEventArgs]::new(0,0);$start.RoutedEvent=[Windows.Controls.Primitives.Thumb]::DragStartedEvent;$thumb.RaiseEvent($start)
$delta=[Windows.Controls.Primitives.DragDeltaEventArgs]::new(0,25);$delta.RoutedEvent=[Windows.Controls.Primitives.Thumb]::DragDeltaEvent;$thumb.RaiseEvent($delta)
$complete=[Windows.Controls.Primitives.DragCompletedEventArgs]::new(0,25,$false);$complete.RoutedEvent=[Windows.Controls.Primitives.Thumb]::DragCompletedEvent;$thumb.RaiseEvent($complete)
$hostVisual.UpdateLayout()
if($scroll.VerticalOffset -le $before){throw 'Dragging the scrollbar did not scroll'}
$scroll.ScrollToEnd();$hostVisual.UpdateLayout()
$done=$w.FindName('Done');$bounds=$done.TransformToAncestor($hostVisual).TransformBounds([Windows.Rect]::new(0,0,$done.ActualWidth,$done.ActualHeight))
if($bounds.Bottom -gt 850 -or $bounds.Top -lt 0){throw 'Bottom action clipped'}
'PASS: settings slider and scrollbar layout, scrolling and footer'
