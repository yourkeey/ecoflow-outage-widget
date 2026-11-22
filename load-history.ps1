function Get-LoadDeviceHash($serial){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$serial)))).Replace('-','')}finally{$sha.Dispose()}
}
function Trim-LoadSamples($samples,$now){
 $cutoff=$now.ToUniversalTime().AddMinutes(-46)
 @($samples | Where-Object {$_.At -ge $cutoff -and $_.At -le $now.ToUniversalTime().AddSeconds(5)} | Sort-Object At | Select-Object -Last 2048)
}
function Initialize-LoadHistory($serial){
 $script:loadDeviceHash=Get-LoadDeviceHash $serial
 $script:loadSamples=@();$script:loadVersion=0
 if(!(Test-Path -LiteralPath $script:loadHistoryPath)){return}
 try{
  $saved=Get-Content -LiteralPath $script:loadHistoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if($saved.device -ne $script:loadDeviceHash){return}
  $samples=@(foreach($sample in $saved.samples){
   try{
    $at=[DateTimeOffset]::Parse($sample.at).UtcDateTime;$watts=[double]$sample.watts
    if(![double]::IsNaN($watts) -and ![double]::IsInfinity($watts) -and $watts -ge 0 -and $watts -le 20000){[pscustomobject]@{At=$at;Watts=$watts}}
   }catch{}
  })
  $script:loadSamples=@(Trim-LoadSamples $samples ([datetime]::UtcNow))
 }catch{}
}
function Add-LoadSample($watts,$at,$serial){
 if($null -eq $watts -or [double]::IsNaN($watts) -or [double]::IsInfinity($watts) -or $watts -lt 0 -or $watts -gt 20000){return}
 $hash=Get-LoadDeviceHash $serial
 if($hash -ne $script:loadDeviceHash){$script:loadDeviceHash=$hash;$script:loadSamples=@()}
 $stamp=$at.ToUniversalTime()
 $script:loadSamples=@($script:loadSamples | Where-Object At -ne $stamp)+[pscustomobject]@{At=$stamp;Watts=[double]$watts}
 $script:loadSamples=@(Trim-LoadSamples $script:loadSamples $stamp)
 $script:loadVersion++
 try{
  $samples=@(foreach($sample in $script:loadSamples){@{at=$sample.At.ToString('o');watts=$sample.Watts}})
  $temporary=$script:loadHistoryPath+'.tmp'
  @{device=$script:loadDeviceHash;samples=$samples} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
  Move-Item -LiteralPath $temporary -Destination $script:loadHistoryPath -Force
 }catch{}
}
function Get-LoadPlot($samples,$now,$width,$height){
 $from=$now.ToUniversalTime().AddMinutes(-45);$to=$now.ToUniversalTime()
 $visible=@($samples | Where-Object {$_.At -ge $from -and $_.At -le $to} | Sort-Object At)
 $max=0;foreach($sample in $visible){if($sample.Watts -gt $max){$max=$sample.Watts}}
 $top=[math]::Max(50,[math]::Ceiling($max/50)*50)
 $groups=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new();$previous=$null
 foreach($sample in $visible){
  if($previous -and ($sample.At-$previous).TotalSeconds -gt 90){$groups.Add($points.ToArray());$points=[Collections.Generic.List[object]]::new()}
  $point=[pscustomobject]@{X=2+($width-4)*($sample.At-$from).TotalSeconds/2700;Y=2+($height-4)*(1-$sample.Watts/$top);Sample=$sample}
  $points.Add($point);$previous=$sample.At
 }
 if($points.Count){$groups.Add($points.ToArray())}
 [pscustomobject]@{Groups=$groups;Samples=$visible;Top=$top;From=$from;To=$to}
}
