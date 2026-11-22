$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'load-history.ps1')
$script:loadHistoryPath=Join-Path $PSScriptRoot 'load-history-model-test.json'
function Assert-Equal($actual,$expected,$message){if($actual -ne $expected){throw $message}}
try{
 $now=[datetime]::UtcNow
 Initialize-LoadHistory 'TEST-A'
 Add-LoadSample 40 $now.AddMinutes(-44) 'TEST-A';Add-LoadSample 80 $now 'TEST-A'
 Assert-Equal $script:loadSamples.Count 2 'Samples missing'
 Initialize-LoadHistory 'TEST-A'
 Assert-Equal $script:loadSamples.Count 2 'History did not survive reload'
 foreach($invalid in @($null,-1,[double]::NaN,[double]::PositiveInfinity,30000)){Add-LoadSample $invalid $now 'TEST-A'}
 Assert-Equal $script:loadSamples.Count 2 'Invalid sample recorded'
 Add-LoadSample 0 $now 'TEST-A'
 Assert-Equal $script:loadSamples.Count 2 'Duplicate timestamp added'
 Assert-Equal $script:loadSamples[-1].Watts 0 'Zero load discarded'
 $samples=@(
  [pscustomobject]@{At=$now.AddMinutes(-46);Watts=999},
  [pscustomobject]@{At=$now.AddMinutes(-5);Watts=20},
  [pscustomobject]@{At=$now.AddSeconds(-270);Watts=80},
  [pscustomobject]@{At=$now;Watts=40}
 )
 $plot=Get-LoadPlot $samples $now 100 40
 Assert-Equal $plot.Samples.Count 3 '45-minute window incorrect'
 Assert-Equal $plot.Groups.Count 2 'Offline gap was connected'
 Assert-Equal $plot.Top 100 'Chart scale includes stale samples'
 $last=$plot.Groups[1][0]
 Assert-Equal $last.X 98 'Latest sample is not at right edge'
 if($last.Y -lt 2 -or $last.Y -gt 38){throw 'Point outside chart'}
 $trimmed=@(Trim-LoadSamples $samples $now.AddMinutes(2))
 Assert-Equal $trimmed.Count 3 'Old samples not removed correctly'
 Add-LoadSample 55 $now 'TEST-B'
 Assert-Equal $script:loadSamples.Count 1 'New station mixed old history'
 Initialize-LoadHistory 'TEST-A'
 Assert-Equal $script:loadSamples.Count 0 'Wrong station history loaded'
 '{broken json' | Set-Content -LiteralPath $script:loadHistoryPath -Encoding UTF8
 Initialize-LoadHistory 'TEST-B'
 Assert-Equal $script:loadSamples.Count 0 'Corrupt history not handled'
 'PASS: history persistence, invalid values, zero watts, duplicate timestamps, 45-minute window, offline gaps, scale, station isolation'
}finally{Remove-Item -LiteralPath $script:loadHistoryPath -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ($script:loadHistoryPath+'.tmp') -ErrorAction SilentlyContinue}
