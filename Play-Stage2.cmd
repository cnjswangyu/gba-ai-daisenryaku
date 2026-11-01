@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -X utf8 -u tools\play_stage2.py %*
set "STAGE2_EXIT=%ERRORLEVEL%"
pause
exit /b %STAGE2_EXIT%
