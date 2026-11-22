$ErrorActionPreference='Stop'
$launcher=Join-Path $PSScriptRoot 'EcoFlow Widget.exe'
if(!(Test-Path -LiteralPath $launcher)){throw 'Launcher not found'}
$folder=[Environment]::GetFolderPath('Startup')
$linkPath=Join-Path $folder 'EcoFlow Widget.lnk'
$shell=New-Object -ComObject WScript.Shell
$link=$shell.CreateShortcut($linkPath)
$link.TargetPath=$launcher
$link.Arguments='--hidden'
$link.IconLocation=$launcher+',0'
$link.WorkingDirectory=$PSScriptRoot
$link.Description='EcoFlow RIVER 2 Pro — заряд рядом с часами'
$link.WindowStyle=7
$link.Save()
if(!(Test-Path -LiteralPath $linkPath)){throw 'Autostart shortcut was not created'}
$legacyLink=Join-Path $folder 'EcoFlow RIVER Widget.lnk'
if(Test-Path -LiteralPath $legacyLink){
 $legacy=$shell.CreateShortcut($legacyLink)
 if($legacy.Arguments -eq ('"'+(Join-Path $PSScriptRoot 'Start.vbs')+'" --hidden')){
  Remove-Item -LiteralPath $legacyLink
 }
}
'Автозапуск включён: виджет будет запускаться в трее при входе в Windows.'
