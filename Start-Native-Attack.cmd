@echo off
cd /d "%~dp0"
powershell -NoProfile -File "%~dp0tools\start_native_attack.ps1"
if errorlevel 1 pause
