@echo off
chcp 65001 >nul
cd /d "%~dp0"
python -X utf8 -u tools\view_map.py %*
set "VIEW_MAP_EXIT=%ERRORLEVEL%"
pause
exit /b %VIEW_MAP_EXIT%
