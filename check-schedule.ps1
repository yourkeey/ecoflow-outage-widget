param([switch]$AsJob)
$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'schedule-ui.ps1') -Raw
$tokens=$null;$errors=$null
$tree=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
$assignment=$tree.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$scheduleWorker'},$true)
Invoke-Expression $assignment.Extent.Text
$zone=[TimeZoneInfo]::FindSystemTimeZoneById('FLE Standard Time');$utc=[datetime]::UtcNow
$local=[TimeZoneInfo]::ConvertTimeFromUtc($utc,$zone)
$stamp=[DateTimeOffset]::new($local,$zone.GetUtcOffset($utc)).ToString('o')
if($AsJob){
 $job=Start-Job -ScriptBlock $scheduleWorker -ArgumentList $PSScriptRoot,$stamp
 $done=Wait-Job $job -Timeout 65
 if(!$done){Stop-Job $job;Remove-Job $job;throw 'Schedule job timed out'}
 $result=Receive-Job $job;Remove-Job $job
}else{$result=& $scheduleWorker $PSScriptRoot $stamp}
[pscustomobject]@{Ok=$result.Ok;Cached=$result.cached;Error=$result.error;Dates=(@($result.days.date) -join ', ')} | ConvertTo-Json
if(!$result.Ok -or $result.cached){exit 1}
