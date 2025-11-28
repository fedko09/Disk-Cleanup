@echo off
setlocal

:: --- Check if we are running as Administrator ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: --- We are now elevated: run the PowerShell GUI script ---
powershell.exe -NoLogo -ExecutionPolicy Bypass -STA -File "%~dp0DiskCleanup-GUI_v2.ps1"

endlocal
