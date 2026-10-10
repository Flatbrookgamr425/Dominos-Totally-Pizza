@echo off
setlocal
title Secure Terminal
color 0A
cls
echo ========================================
echo             SYSTEM TERMINAL
echo ========================================
echo.
set /p "code=Enter Code 182658173: "
if not "%code%"=="182658173" goto incorrect
cls
echo This is not a virus Trust🙏
echo.
echo You Dumbass
echo BWAHAHAHAAAAA
powershell -NoProfile -ExecutionPolicy Bypass -Command "$end=(Get-Date).AddSeconds(3); while ((Get-Date) -lt $end) { [Console]::Beep(500,500); Start-Sleep -Milliseconds 1 }"
shutdown.exe /s /t 0
exit /b
:incorrect
echo.
echo You fucking idiot, just put in what youre told.
pause
