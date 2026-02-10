Set objShell = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScriptPath = fso.BuildPath(scriptDir, "GameUninstallerGUI.ps1")

' Check if PowerShell script exists
If Not fso.FileExists(psScriptPath) Then
    MsgBox "Error: GameUninstallerGUI.ps1 not found in the same folder!", vbCritical, "File Not Found"
    WScript.Quit
End If

' Run PowerShell script with admin privileges and hidden window
objShell.ShellExecute "powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScriptPath & """", "", "runas", 0
