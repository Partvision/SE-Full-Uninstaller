@echo off
setlocal enabledelayedexpansion
title Temp Cleaner Pro
echo.
echo ========================================
echo          TEMP CLEANER PRO
echo ========================================
echo.

:: Get initial disk space in MB using PowerShell
for /f %%a in ('powershell -command "[math]::Round((Get-PSDrive C).Free/1MB)"') do set BEFORE=%%a

echo [*] Cleaning in progress...
echo.

:: Clean user temp files
echo [1/12] User temp files...
del /f /s /q "%TEMP%\*" >nul 2>&1
for /d %%x in ("%TEMP%\*") do rd /s /q "%%x" >nul 2>&1

:: Clean Windows temp files
echo [2/12] Windows temp files...
del /f /s /q "C:\Windows\Temp\*" >nul 2>&1
for /d %%x in ("C:\Windows\Temp\*") do rd /s /q "%%x" >nul 2>&1

:: Clean Prefetch
echo [3/12] Prefetch...
del /f /s /q "C:\Windows\Prefetch\*" >nul 2>&1

:: Clean Windows Update cache
echo [4/12] Windows Update cache...
del /f /s /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
for /d %%x in ("C:\Windows\SoftwareDistribution\Download\*") do rd /s /q "%%x" >nul 2>&1

:: Clean Windows Error Reporting
echo [5/12] Error reports...
del /f /s /q "C:\ProgramData\Microsoft\Windows\WER\*" >nul 2>&1
for /d %%x in ("C:\ProgramData\Microsoft\Windows\WER\*") do rd /s /q "%%x" >nul 2>&1

:: Clean thumbnail cache
echo [6/12] Thumbnail cache...
del /f /s /q "%LocalAppData%\Microsoft\Windows\Explorer\*.db" >nul 2>&1

:: Clean browser caches (Chrome)
echo [7/12] Chrome cache...
del /f /s /q "%LocalAppData%\Google\Chrome\User Data\Default\Cache\*" >nul 2>&1
for /d %%x in ("%LocalAppData%\Google\Chrome\User Data\Default\Cache\*") do rd /s /q "%%x" >nul 2>&1

:: Clean browser caches (Edge)
echo [8/12] Edge cache...
del /f /s /q "%LocalAppData%\Microsoft\Edge\User Data\Default\Cache\*" >nul 2>&1
for /d %%x in ("%LocalAppData%\Microsoft\Edge\User Data\Default\Cache\*") do rd /s /q "%%x" >nul 2>&1

:: Clean Windows logs
echo [9/12] Windows logs...
del /f /q "C:\Windows\Logs\*.log" >nul 2>&1
del /f /q "C:\Windows\Logs\CBS\*.log" >nul 2>&1

:: Clean Recent Items
echo [10/12] Recent items...
del /f /s /q "%AppData%\Microsoft\Windows\Recent\*" >nul 2>&1

:: Clean Windows Installer cache
echo [11/12] Installer cache...
del /f /s /q "C:\Windows\Installer\$PatchCache$\*" >nul 2>&1

:: Empty Recycle Bin
echo [12/12] Recycle Bin...
PowerShell -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1

:: Get final disk space in MB
for /f %%a in ('powershell -command "[math]::Round((Get-PSDrive C).Free/1MB)"') do set AFTER=%%a

:: Calculate MB freed
set /a FREED=%AFTER%-%BEFORE%

:: Handle negative values
if %FREED% LSS 0 set /a FREED=-%FREED%

echo.
echo ========================================
echo   DONE! Freed: %FREED% MB
echo ========================================
echo.
pause