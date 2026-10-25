@echo off
setlocal
title Certificate Toolkit
cd /d "%~dp0"

if not exist "%~dp0CertToolkit.ps1" (
  echo.
  echo  [ERROR] CertToolkit.ps1 not found in this folder.
  echo          Please keep the whole folder together.
  echo.
  pause
  exit /b 1
)

echo.
echo  Starting Certificate Toolkit ...
echo.

rem Windows PowerShell 5.1 is always present on Windows and always has WinForms.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0CertToolkit.ps1"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
  echo.
  echo  [ERROR] Exit code %RC%
  echo.
  echo  Try running it manually:
  echo    powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0CertToolkit.ps1"
  echo    pwsh.exe       -NoProfile -File "%~dp0CertToolkit.ps1"
  echo.
  echo  For the command line version:
  echo    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0csrtool.ps1" --help
  echo.
  pause
)

exit /b %RC%
