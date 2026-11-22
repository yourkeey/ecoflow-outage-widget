$ErrorActionPreference='Stop'
$source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'widget.ps1') -Raw
$tokens=$null;$parseErrors=$null
$tree=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
$assignment=$tree.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$worker'},$true)
Invoke-Expression $assignment.Extent.Text
. (Join-Path $PSScriptRoot 'connection-config.ps1')
$cfg=Get-EcoFlowConnection $PSScriptRoot
if(!$cfg){throw 'No EcoFlow connection configured.'}
$job=Start-Job -ScriptBlock $worker -ArgumentList $cfg,$PSScriptRoot,$null
$done=Wait-Job $job -Timeout 85
if(!$done){Stop-Job $job;Remove-Job $job;throw 'Diagnostic timed out'}
$result=Receive-Job $job -ErrorAction SilentlyContinue
Remove-Job $job
# Never output credentials, session tokens, raw replies, or account/device identifiers.
[pscustomobject]@{Ok=$result.Ok;Error=$result.Error;Diagnostic=$result.Diagnostic;HasData=($null -ne $result.Data)} | ConvertTo-Json -Depth 6
