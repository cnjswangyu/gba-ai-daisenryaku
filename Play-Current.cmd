@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -X utf8 -u tools\play_current.py %*
set "PLAY_EXIT=%ERRORLEVEL%"
pause
exit /b %PLAY_EXIT%
