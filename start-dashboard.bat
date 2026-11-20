@echo off
title Waterproofing Dashboard - localhost
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1" -Port 9375
if errorlevel 1 (
  echo.
  echo Login server could not start - starting the basic server instead...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server_basic.ps1" -Port 9375
)
pause
