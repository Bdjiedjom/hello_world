@echo off
title Wi-Fi Zone - Activer internet
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WifiZone-Proxy.ps1" -Action Activer
echo.
pause
