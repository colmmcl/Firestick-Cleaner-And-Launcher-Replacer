@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Firestick Cleanup Tool v2.0 - AT4K Edition
color 0A

:: ============================================================
:: CONFIGURATION
:: ============================================================

set "VERSION=2.0"
set "ADB=%~dp0adb\adb.exe"
set "SCRIPT_DIR=%~dp0"

set "TMP=%TEMP%\FirestickCleanup.tmp"
set "LOG=%SCRIPT_DIR%FirestickCleanup.log"

:: ---------- AT4K ----------
set "AT4K_PKG=com.overdevs.at4k"
set "AT4K_ACTIVITY=%AT4K_PKG%/.MainActivity"
set "AT4K_ACCESSIBILITY=%AT4K_PKG%/.Hra"

:: ---------- LOG ----------
(
echo ============================================
echo Firestick Cleanup Tool v%VERSION%
echo Started %DATE% %TIME%
echo ============================================
)> "%LOG%"
cls
echo.
echo ===========================================================
echo            FIRESTICK CLEANUP TOOL v%VERSION%
echo                    AT4K EDITION
echo ===========================================================
echo.

if not exist "%ADB%" (
    echo.
    echo ERROR:
    echo adb.exe was not found.
    echo.
    echo Expected:
    echo %ADB%
    echo.
    pause
    exit /b
)

echo [OK] ADB found.

echo.
set /p FIRE_IP=Enter Fire TV IP Address:

if "%FIRE_IP%"=="" (
    echo.
    echo No IP entered.
    pause
    exit /b
)

set TARGET=-s %FIRE_IP%:5555

echo.
echo Connecting...

"%ADB%" disconnect >nul 2>&1
"%ADB%" connect %FIRE_IP%:5555

echo.
echo Accept the ADB prompt on the TV.
pause

"%ADB%" %TARGET% shell echo Connected>"%TMP%"

findstr "Connected" "%TMP%" >nul

if errorlevel 1 (
    echo.
    echo Connection failed.
    pause
    exit /b
)

echo.
echo Connected successfully.

set APK=

for %%F in (

"AT4K.apk"

"base.apk"

"at4k*.apk"

"*.apk"

) do (

if not defined APK (
for %%A in (%%~F) do (

if exist "%%~A" (

set APK=%%~fA

)

)

)

)

if not defined APK (

echo.

echo No AT4K APK found.

echo.

echo Copy one of these into this folder:

echo.

echo    AT4K.apk

echo    base.apk

echo    at4k_0.99.apk

pause

exit /b

)

echo.

echo Found:

echo %APK%

:: ============================================================
:: STEP 2 - Install / Update AT4K
:: ============================================================

echo.
echo ============================================
echo STEP 2 - Installing AT4K Launcher
echo ============================================

echo Checking for existing installation...

"%ADB%" %TARGET% shell pm path %AT4K_PKG% >"%TMP%" 2>&1

findstr "package:" "%TMP%" >nul

if not errorlevel 1 (
    echo.
    echo AT4K is already installed.
    echo.
    choice /C YN /M "Reinstall AT4K"
    if errorlevel 2 goto ConfigureAT4K
)

echo.
echo Uploading APK...

"%ADB%" %TARGET% push "%APK%" /data/local/tmp/AT4K.apk

if errorlevel 1 (
    echo.
    echo Upload failed.
    pause
    exit /b
)

echo.
echo Installing...

"%ADB%" %TARGET% shell pm install -r /data/local/tmp/AT4K.apk >"%TMP%" 2>&1

findstr "Success" "%TMP%" >nul

if errorlevel 1 (
    echo.
    echo Installation failed.
    type "%TMP%"
    pause
    exit /b
)

echo.
echo Installation successful.

"%ADB%" %TARGET% shell rm /data/local/tmp/AT4K.apk

:ConfigureAT4K

echo.
echo ============================================
echo STEP 3 - Configuring AT4K
echo ============================================

echo.
echo Enabling Accessibility Service...

"%ADB%" %TARGET% shell settings put secure enabled_accessibility_services %AT4K_ACCESSIBILITY%

"%ADB%" %TARGET% shell settings put secure accessibility_enabled 1

echo.
echo Verifying...

"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services >"%TMP%"

findstr "%AT4K_PKG%" "%TMP%" >nul

if errorlevel 1 (
    echo.
    echo WARNING:
    echo Accessibility service was not enabled.
) else (
    echo Accessibility enabled.
)


echo.
echo Setting Home launcher...

"%ADB%" %TARGET% shell cmd role add-role-holder android.app.role.HOME %AT4K_PKG%

echo.
echo Launching AT4K...

"%ADB%" %TARGET% shell am start -n %AT4K_ACTIVITY% >"%TMP%" 2>&1

findstr "Error" "%TMP%" >nul

if errorlevel 1 (
    echo AT4K launched successfully.
) else (
    echo.
    echo Direct launch failed.
    echo Trying Leanback launcher...

    "%ADB%" %TARGET% shell monkey -p %AT4K_PKG% -c android.intent.category.LEANBACK_LAUNCHER 1
)

echo.

echo =======================================================
echo                 ACTION REQUIRED
echo =======================================================
echo.
echo On your Fire TV:
echo.
echo 1. Open AT4K Launcher
echo 2. Grant any requested permissions
echo 3. Enable Accessibility if prompted
echo 4. Select AT4K as your Home launcher if Fire OS asks
echo.
pause

echo.
echo ============================================
echo STEP 4 - Scanning Installed Packages
echo ============================================

echo Building package database...

"%ADB%" %TARGET% shell pm list packages > "%TMP%.packages"

if errorlevel 1 (
    echo Failed to read installed packages.
    pause
    exit /b
)

echo Package database created.

set BLOAT=^
com.amazon.tv.acr ^
com.amazon.hybridadidservice ^
com.amazon.device.telemetry.emitter ^
com.amazon.wirelessmetrics.service ^
com.amazon.perfc ^
com.amazon.perfcollection ^
com.amazon.shoptv.client ^
com.amazon.shoptv.firetv.client ^
com.amazon.sneakpeek ^
com.amazon.ftv.screensaver ^
com.amazon.storm.lightning.tutorial ^
com.amazon.tmm.tutorial ^
com.amazon.tv.releasenotes ^
com.amazon.fireos.cirruscloud ^
com.amazon.device.rdmapplication ^
com.amazon.aria ^
com.amazon.hedwig ^
com.amazon.logan ^
com.amazon.tv.support ^
com.amazon.tv.turnstile ^
com.amazon.tv.ftvambient ^
com.amazon.notificationcenter ^
com.amazon.privacypassservice

echo.
echo ============================================
echo STEP 5 - Disabling Amazon Bloat
echo ============================================

set DISABLED=0
set SKIPPED=0

for %%P in (%BLOAT%) do (

    findstr /I "package:%%P" "%TMP%.packages" >nul

    if errorlevel 1 (

        echo Skipping %%P
        set /a SKIPPED+=1

    ) else (

        echo Disabling %%P...

        "%ADB%" %TARGET% shell pm disable-user --user 0 %%P > "%TMP%"

        findstr "disabled-user" "%TMP%" >nul

        if errorlevel 1 (

            echo Protected

        ) else (

            echo Disabled
            set /a DISABLED+=1

        )

    )

)

echo.
echo ============================================
echo Debloat Summary
echo ============================================

echo Disabled : %DISABLED%
echo Skipped  : %SKIPPED%

echo.
echo ============================================
echo STEP 6 - Rebooting Fire TV
echo ============================================

echo Rebooting...

"%ADB%" %TARGET% shell reboot

echo Waiting for device...
timeout /t 35 /nobreak >nul

set RECONNECTED=0

for /L %%I in (1,1,20) do (

    "%ADB%" connect %FIRE_IP%:5555 >nul 2>&1

    "%ADB%" %TARGET% shell echo ONLINE>"%TMP%" 2>&1

    findstr "ONLINE" "%TMP%" >nul

    if not errorlevel 1 (

        set RECONNECTED=1
        goto DeviceOnline

    )

    echo Waiting... %%I/20
    timeout /t 3 /nobreak >nul

)

:DeviceOnline

if "%RECONNECTED%"=="0" (

    echo.
    echo Device never came back online.
    pause
    exit /b

)

echo.
echo Fire TV reconnected.

echo.
echo ============================================
echo STEP 7 - Verification
echo ============================================

"%ADB%" %TARGET% shell pm path %AT4K_PKG%>"%TMP%"

findstr "package:" "%TMP%" >nul

if errorlevel 1 (

    echo.
    echo ERROR:
    echo AT4K Launcher is missing.
    pause
    exit /b

)

echo AT4K installed.

"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services>"%TMP%"

findstr "%AT4K_PKG%" "%TMP%" >nul

if errorlevel 1 (

    echo.
    echo Accessibility NOT enabled.

) else (

    echo Accessibility OK.

)

echo.
echo ============================================
echo STEP 8 - RAM Usage
echo ============================================

"%ADB%" %TARGET% shell cat /proc/meminfo>"%TMP%"

for /f "tokens=2" %%A in ('findstr "MemAvailable" "%TMP%"') do (
    set /a RAM=%%A/1024
)

echo.
echo Available RAM : %RAM% MB

echo.
echo ============================================
echo COMPLETE
echo ============================================

echo.
echo AT4K Launcher Installed

echo Debloat Complete

echo Fire TV Optimized

echo.
echo Log File:

echo %LOG%

echo.

pause
goto End

:Revert

echo.
echo Re-enabling disabled packages...

"%ADB%" %TARGET% shell pm list packages -d>"%TMP%"

for /f "tokens=2 delims=:" %%P in ('type "%TMP%"') do (

    "%ADB%" %TARGET% shell pm enable %%P

)

echo.
echo Removing AT4K...

"%ADB%" %TARGET% shell pm uninstall %AT4K_PKG%

echo.
echo Done.

pause

goto End

:End

del "%TMP%" >nul 2>&1
del "%TMP%.packages" >nul 2>&1

endlocal
exit








