@echo off
title Game Uninstaller Pro - Launcher

:: Check for admin and create hidden launcher
net file 1>nul 2>nul
if '%errorlevel%' == '0' ( goto runScript )

:: Create VBS for hidden admin elevation
echo Set objShell = CreateObject("Shell.Application") > "%temp%\elevate.vbs"
echo objShell.ShellExecute "cmd.exe", "/c """"%~f0""""", "", "runas", 0 >> "%temp%\elevate.vbs"
cscript //nologo "%temp%\elevate.vbs"
del "%temp%\elevate.vbs"
exit /b

:runScript
:: Run PowerShell GUI hidden
powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%~dp0GameUninstallerGUI.ps1"
exit
