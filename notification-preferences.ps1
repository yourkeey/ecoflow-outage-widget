function Get-NotificationDefaults { @{LowBattery=$true;TwoHours=$true;FifteenMinutes=$true;ScheduleChanges=$true;CustomReminder=$false;CustomMinutes=60} }
if(!$script:notificationPrefs){$script:notificationPrefs=Get-NotificationDefaults}
function Test-NotificationEnabled($name){
 if(!$script:notificationPrefs -or !$script:notificationPrefs.ContainsKey($name)){return $true}
 return [bool]$script:notificationPrefs[$name]
}
function Read-NotificationPreferences {
 $script:notificationPrefs=Get-NotificationDefaults
 if(Test-Path -LiteralPath $script:notificationSettingsPath){try{
  $saved=Get-Content -LiteralPath $script:notificationSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach($key in @($script:notificationPrefs.Keys)){
   $property=$saved.PSObject.Properties[$key]
   if($key -eq 'CustomMinutes'){
    $number=0
    if($property -and [int]::TryParse([string]$property.Value,[ref]$number) -and $number -ge 1 -and $number -le 1440){$script:notificationPrefs[$key]=$number}
   }elseif($property -and $property.Value -is [bool]){$script:notificationPrefs[$key]=$property.Value}
  }
 }catch{}}
}
function Save-NotificationPreferences {
 $temporary=$script:notificationSettingsPath+'.tmp'
 $script:notificationPrefs | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
 Move-Item -LiteralPath $temporary -Destination $script:notificationSettingsPath -Force
}
function Get-ReminderSummary {
 $parts=@()
 if(Test-NotificationEnabled 'TwoHours'){$parts+='за 2 ч'}
 if(Test-NotificationEnabled 'FifteenMinutes'){$parts+='за 15 мин'}
 if(Test-NotificationEnabled 'CustomReminder'){$parts+='за '+(Format-LeadMinutes (Get-CustomLeadMinutes))}
 if(!$parts.Count){return 'Напоминания отключены'}
 return (($parts | Select-Object -Unique) -join ', ')
}
function Get-CustomLeadMinutes {
 $value=0
 if($script:notificationPrefs.ContainsKey('CustomMinutes') -and [int]::TryParse([string]$script:notificationPrefs.CustomMinutes,[ref]$value) -and $value -ge 1 -and $value -le 1440){return $value}
 return 60
}
function Format-LeadMinutes($minutes){
 if($minutes -lt 60){return "$minutes мин"}
 $hours=[int][math]::Floor($minutes/60);$rest=$minutes%60
 if($rest -eq 0){return "$hours ч"}
 return ('{0} ч {1:00} мин' -f $hours,$rest)
}
function ConvertTo-CustomLeadMinutes($hoursText,$minutesText){
 if($hoursText -notmatch '^[0-9]{1,2}$' -or $minutesText -notmatch '^[0-9]{1,2}$'){return $null}
 $hours=[int]$hoursText;$minutes=[int]$minutesText
 $total=$hours*60+$minutes
 if($minutes -gt 59 -or $total -lt 1 -or $total -gt 1440){return $null}
 return $total
}
