@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM EduCore360 - Clean device activation state
REM ============================================================
REM Wipes the local activation flag and Credential Manager entry on
REM this PC so the next launch shows the Activate this PC screen.
REM Safe to re-run any number of times. Only touches EduCore360 data.
REM
REM Run by double-clicking, or:  scripts\clean_device_activation.bat
REM ============================================================

echo.
echo EduCore360 device-activation cleaner
echo ------------------------------------

REM 1. Kill the app if it's running (file locks otherwise).
echo Stopping EduCore360 if running...
taskkill /F /IM school_admin.exe >nul 2>&1
if %errorlevel%==0 (echo  - process closed) else (echo  - process not running)

REM 2. Wipe the app's secure storage + shared preferences.
set "DATADIR=%APPDATA%\com.edudesk\EduCore 360"

if exist "%DATADIR%\flutter_secure_storage.dat" (
    del /F /Q "%DATADIR%\flutter_secure_storage.dat"
    echo  - removed flutter_secure_storage.dat
) else (
    echo  - flutter_secure_storage.dat not present
)

if exist "%DATADIR%\shared_preferences.json" (
    del /F /Q "%DATADIR%\shared_preferences.json"
    echo  - removed shared_preferences.json
) else (
    echo  - shared_preferences.json not present
)

REM Drop the now-empty folders (rmdir without /S only removes if empty).
if exist "%DATADIR%"          rmdir "%DATADIR%"          >nul 2>&1
if exist "%APPDATA%\com.edudesk" rmdir "%APPDATA%\com.edudesk" >nul 2>&1

REM 3. Remove the Windows Credential Manager entry that holds the AES
REM    key for flutter_secure_storage. Harmless if not present.
echo Removing secure-storage credential...
cmdkey /delete:key_school_admin_VGhpcyBpcyB0aGUgcHJlZml4IGZv_ >nul 2>&1
if %errorlevel%==0 (echo  - credential removed) else (echo  - no credential to remove)

echo.
echo Done. Launch EduCore360 - it will ask for a fresh activation code.
echo.
pause
endlocal
