@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -X utf8 -u tools\play_stage1.py %*
set "STAGE1_EXIT=%ERRORLEVEL%"
pause
exit /b %STAGE1_EXIT%
