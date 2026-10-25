@echo off
title CSR Generator
cd /d "%~dp0"
echo.
echo  Starting CSR Generator ...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0CSR-Generator.ps1"
if errorlevel 1 (
  echo.
  echo  [ERROR] Failed to start.
  echo  Run manually:
  echo    powershell -ExecutionPolicy Bypass -STA -File "%~dp0CSR-Generator.ps1"
  echo.
  pause
)