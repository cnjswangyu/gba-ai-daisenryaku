@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo === Play-Current2 : multi-faction + city resupply ===
echo Open the game first (battlefield / deployment / scenario select), then run this script.
echo.
python -X utf8 -u tools\play_current2.py %*
set "PLAY_EXIT=%ERRORLEVEL%"
echo.
echo exit code = %PLAY_EXIT%   (0 = victory)
pause
exit /b %PLAY_EXIT%
