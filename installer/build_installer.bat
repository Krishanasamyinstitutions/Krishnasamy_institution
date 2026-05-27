@echo off
REM Build EduCore360 Windows release and produce both the loose zip and the
REM Inno Setup installer in one command.
REM
REM Usage:  cd installer ^&^& build_installer.bat
REM Output: installer\dist\EduCore360-Setup-<version>.exe
REM
REM Prerequisites:
REM   - Flutter on PATH
REM   - Inno Setup 6 (iscc.exe) on PATH or in default install location
setlocal

cd /d "%~dp0\.."

echo === Building Flutter Windows release ===
call flutter build windows --release
if errorlevel 1 (
  echo Flutter build failed.
  exit /b 1
)

echo.
echo === Compiling Inno Setup installer ===
set "ISCC=iscc"
where %ISCC% >nul 2>nul
if errorlevel 1 (
  if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
)
if errorlevel 1 (
  echo Inno Setup compiler (iscc.exe) not found. Install Inno Setup 6 first:
  echo   https://jrsoftware.org/isdl.php
  exit /b 1
)
"%ISCC%" "installer\EduCore360.iss"
if errorlevel 1 (
  echo Inno Setup compile failed.
  exit /b 1
)

echo.
echo === Done ===
echo Installer: installer\dist\EduCore360-Setup-1.0.0.exe
endlocal
