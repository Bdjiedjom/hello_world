@echo off
title Wi-Fi Zone - Desactiver le proxy
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WifiZone-Proxy.ps1" -Action Desactiver
echo.
pause
