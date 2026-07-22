@echo off
REM ============================================================
REM  RDPWrap Self-Heal — one-click install
REM  Right-click -> Run as administrator
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-RDPWrapSelfHeal.ps1" -Mode Install
echo.
echo  Next: open RDP_CnC.exe, then prove with:  query user
echo  Logs: C:\Program Files\RDP Wrapper\logs\
echo.
pause
