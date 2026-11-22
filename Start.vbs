Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
folder = fs.GetParentFolderName(WScript.ScriptFullName)
arguments = ""
If WScript.Arguments.Count > 0 Then
  If WScript.Arguments(0) = "--hidden" Then arguments = " -StartHidden"
End If
shell.Run "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\widget.ps1""" & arguments, 0, False
