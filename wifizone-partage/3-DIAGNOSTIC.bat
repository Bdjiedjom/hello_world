@echo off
title Wi-Fi Zone - Diagnostic
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WifiZone-Proxy.ps1" -Action Diagnostic
echo.
pause
