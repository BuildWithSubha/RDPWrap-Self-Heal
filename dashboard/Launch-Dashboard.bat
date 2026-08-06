@echo off
REM ============================================================
REM  RDPWrap Self-Heal Dashboard Launcher
REM ============================================================
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo.
    echo  [!] RIGHT-CLICK this file and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

cd /d "%~dp0"
echo Starting RDPWrap Self-Heal Dashboard Server...
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DashboardServer.ps1"

timeout /t 2 >nul
echo Opening Dashboard in browser...
start http://localhost:8888
