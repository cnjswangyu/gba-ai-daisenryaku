@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -X utf8 -u tools\farm_stage1.py %*
set "FARM_EXIT=%ERRORLEVEL%"
pause
exit /b %FARM_EXIT%
