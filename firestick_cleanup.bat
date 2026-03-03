@echo off
setlocal enabledelayedexpansion
title Firestick Cleanup Tool
color 0A

set "ADB=%~dp0adb\adb.exe"
set "APK_DIR=%~dp0"
set "PROJECTIVY_PKG=com.spocky.projengmenu"
set "PROJECTIVY_ACTIVITY=%PROJECTIVY_PKG%/.ui.home.MainActivity"
set "PROJECTIVY_ACCESSIBILITY=%PROJECTIVY_PKG%/.services.ProjectivyAccessibilityService"
set "PROJECTIVY_NOTIFICATION=%PROJECTIVY_PKG%/.services.notification.NotificationListener"
set "TMPFILE=%TEMP%\firestick_cleanup_tmp.txt"
set "LOGFILE=%~dp0firestick_cleanup.log"

:: Start fresh log
echo ============================================ >"%LOGFILE%"
echo   Firestick Cleanup Log >>"%LOGFILE%"
echo   Started: %DATE% %TIME% >>"%LOGFILE%"
echo ============================================ >>"%LOGFILE%"
echo. >>"%LOGFILE%"

echo.
echo   ========================================
echo          Firestick Cleanup Tool
echo     Projectivy Launcher + Debloat
echo   ========================================
echo.

:: Check for --revert flag
if "%~1"=="--revert" goto :revert

:: Verify ADB exists
if not exist "%ADB%" (
    echo   [!!] ADB not found at: %ADB%
    echo   [!!] Make sure the adb folder is next to this script.
    goto :fail
)
echo   [OK] ADB found: %ADB%

:: Get Fire TV IP
echo.
set /p "FIRE_IP=  Enter your Fire TV IP address (e.g. 10.0.0.20): "
if "%FIRE_IP%"=="" (
    echo   [!!] No IP provided.
    goto :fail
)

:: Set target device for all subsequent ADB commands
set "TARGET=-s %FIRE_IP%:5555"
echo [CONFIG] IP=%FIRE_IP% TARGET=%TARGET% >>"%LOGFILE%"

:: Disconnect any other devices to avoid conflicts
"%ADB%" disconnect >nul 2>&1

:: ============================================================
:: STEP 1: Connect
:: ============================================================
echo.
echo   ========================================
echo     STEP 1: Connecting to Fire TV at %FIRE_IP%
echo   ========================================

"%ADB%" connect %FIRE_IP%:5555 >nul 2>&1

echo.
echo   A connection request has been sent to your Fire TV.
echo   On your TV screen, select 'Always allow from this computer' and press OK.
echo.
pause

:: Retry connection after user confirms
echo [STEP 1] Connecting to %FIRE_IP%:5555 >>"%LOGFILE%"
"%ADB%" connect %FIRE_IP%:5555 >>"%LOGFILE%" 2>&1
timeout /t 2 /nobreak >nul

"%ADB%" %TARGET% shell echo ok >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"ok" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Connected to %FIRE_IP%:5555
    echo [STEP 1] Connected OK >>"%LOGFILE%"
) else (
    echo   [!!] Could not connect. Make sure:
    echo       1. Fire TV and this computer are on the same network
    echo       2. ADB Debugging is enabled on the Fire TV
    echo       3. You authorized the connection on the TV screen
    echo [STEP 1] FAILED to connect >>"%LOGFILE%"
    goto :fail
)

:: ============================================================
:: BASELINE: Capture RAM before cleanup
:: ============================================================
echo.
echo   ========================================
echo     BASELINE: Capturing RAM Usage
echo   ========================================

set "RAM_BEFORE_TOTAL=0"
set "RAM_BEFORE_AVAIL=0"
set "RAM_BEFORE_USED=0"
set "PROCS_BEFORE=0"

:: Get memory info by running grep on the device side
"%ADB%" %TARGET% shell "cat /proc/meminfo | grep MemTotal" >"%TMPFILE%" 2>&1
for /f "tokens=2" %%a in ('type "%TMPFILE%" 2^>nul') do set /a "RAM_BEFORE_TOTAL=%%a / 1024"

"%ADB%" %TARGET% shell "cat /proc/meminfo | grep MemAvailable" >"%TMPFILE%" 2>&1
for /f "tokens=2" %%a in ('type "%TMPFILE%" 2^>nul') do set /a "RAM_BEFORE_AVAIL=%%a / 1024"

set /a "RAM_BEFORE_USED=RAM_BEFORE_TOTAL - RAM_BEFORE_AVAIL"

"%ADB%" %TARGET% shell "ps -A | grep com.amazon | wc -l" >"%TMPFILE%" 2>&1
for /f "tokens=1" %%a in ('type "%TMPFILE%" 2^>nul') do set "PROCS_BEFORE=%%a"

echo   [OK] Total RAM:        !RAM_BEFORE_TOTAL! MB
echo   [OK] Available RAM:    !RAM_BEFORE_AVAIL! MB
echo   [OK] Used RAM:         !RAM_BEFORE_USED! MB
echo   [OK] Amazon processes: !PROCS_BEFORE! running

:: ============================================================
:: STEP 2: Download Projectivy
:: ============================================================
echo.
echo   ========================================
echo     STEP 2: Downloading Projectivy Launcher
echo   ========================================

:: Check if an APK already exists
set "APK_FILE="
for %%f in ("%APK_DIR%ProjectivyLauncher-*.apk") do set "APK_FILE=%%f"

if defined APK_FILE (
    echo   [OK] APK already exists: !APK_FILE!
    goto :install
)

:: Download latest release using curl (built into Windows 10+)
echo   [..] Fetching latest release info from GitHub...

:: Save full API response to temp file, then extract APK URL
curl -s "https://api.github.com/repos/spocky/miproja1/releases/latest" >"%TMPFILE%" 2>nul

set "APK_URL="
for /f "usebackq tokens=*" %%a in ("%TMPFILE%") do (
    set "LINE=%%a"
    echo !LINE! | findstr /C:"browser_download_url" | findstr /C:".apk" >nul 2>&1
    if !errorlevel!==0 (
        :: Extract URL - find everything between quotes after browser_download_url
        set "CLEAN=!LINE!"
        :: Remove everything up to and including "browser_download_url": "
        for /f "tokens=2 delims=@" %%u in ("!CLEAN:browser_download_url=@!") do (
            set "URL_PART=%%u"
        )
        :: Clean up: remove leading/trailing quotes, spaces, commas
        set "URL_PART=!URL_PART: =!"
        set "URL_PART=!URL_PART:"=!"
        set "URL_PART=!URL_PART:,=!"
        if not "!URL_PART!"=="" set "APK_URL=!URL_PART!"
    )
)

if not defined APK_URL (
    echo   [..] Could not parse latest release. Using known working version...
    set "APK_URL=https://github.com/spocky/miproja1/releases/download/4.68/ProjectivyLauncher-4.68-c82-xda-release.apk"
)

:: Trim any leading colon or space from URL
if "!APK_URL:~0,1!"==":" set "APK_URL=!APK_URL:~1!"
if "!APK_URL:~0,1!"==" " set "APK_URL=!APK_URL:~1!"

echo   [..] Downloading: !APK_URL!
set "APK_FILE=%APK_DIR%ProjectivyLauncher-latest.apk"
curl -L -o "!APK_FILE!" "!APK_URL!"

if not exist "!APK_FILE!" (
    echo   [!!] Download failed.
    goto :fail
)

for %%A in ("!APK_FILE!") do set "APK_SIZE=%%~zA"
if "!APK_SIZE!"=="" (
    echo   [!!] Download failed - file is empty.
    goto :fail
)
if !APK_SIZE! LSS 100000 (
    echo   [!!] Download failed - file too small.
    del "!APK_FILE!" >nul 2>&1
    goto :fail
)

set /a "SIZE_MB=!APK_SIZE! / 1048576"
echo   [OK] Downloaded (!SIZE_MB! MB^)

:: ============================================================
:: STEP 3: Install Projectivy
:: ============================================================
:install
echo.
echo   ========================================
echo     STEP 3: Installing Projectivy Launcher
echo   ========================================

echo   [..] Pushing APK to device...
echo [STEP 3] Pushing APK: !APK_FILE! >>"%LOGFILE%"
"%ADB%" %TARGET% push "!APK_FILE!" /data/local/tmp/projectivy.apk >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"pushed" "%TMPFILE%" >nul 2>&1
if !errorlevel! neq 0 (
    echo   [!!] Failed to push APK to device.
    type "%TMPFILE%"
    goto :fail
)
echo   [OK] APK pushed to device

echo   [..] Installing...
echo [STEP 3] Running: pm install -r /data/local/tmp/projectivy.apk >>"%LOGFILE%"
"%ADB%" %TARGET% shell pm install -r /data/local/tmp/projectivy.apk >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"Success" "%TMPFILE%" >nul 2>&1
if !errorlevel! neq 0 (
    echo   [!!] Install failed.
    type "%TMPFILE%"
    goto :fail
)

:: Verify the package actually exists on device
echo [STEP 3] Verifying package path... >>"%LOGFILE%"
"%ADB%" %TARGET% shell pm path %PROJECTIVY_PKG% >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"package:" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Projectivy Launcher installed and verified
) else (
    echo   [!!] Install reported success but package not found on device.
    goto :fail
)

:: Clean up temp APK on device
"%ADB%" %TARGET% shell rm /data/local/tmp/projectivy.apk >nul 2>&1

:: ============================================================
:: STEP 4: Configure as default launcher
:: ============================================================
echo.
echo   ========================================
echo     STEP 4: Configuring Projectivy
echo   ========================================

:: Enable accessibility service
echo [STEP 4] Setting accessibility service... >>"%LOGFILE%"
"%ADB%" %TARGET% shell settings put secure enabled_accessibility_services %PROJECTIVY_ACCESSIBILITY% >>"%LOGFILE%" 2>&1
"%ADB%" %TARGET% shell settings put secure accessibility_enabled 1 >>"%LOGFILE%" 2>&1

:: Verify
"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"%PROJECTIVY_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Accessibility service enabled
) else (
    echo   [!!] Could not enable accessibility service
    goto :fail
)

:: Notification listener
echo [STEP 4] Setting notification listener... >>"%LOGFILE%"
"%ADB%" %TARGET% shell settings put secure enabled_notification_listeners %PROJECTIVY_NOTIFICATION% >>"%LOGFILE%" 2>&1
echo   [OK] Notification listener enabled

:: Overlay permission
echo [STEP 4] Setting overlay permission... >>"%LOGFILE%"
"%ADB%" %TARGET% shell appops set %PROJECTIVY_PKG% SYSTEM_ALERT_WINDOW allow >>"%LOGFILE%" 2>&1
echo   [OK] Overlay permission granted

:: HOME role
echo [STEP 4] Setting HOME role... >>"%LOGFILE%"
"%ADB%" %TARGET% shell cmd role add-role-holder android.app.role.HOME %PROJECTIVY_PKG% >>"%LOGFILE%" 2>&1
echo   [OK] HOME role assigned

:: Launch it
echo [STEP 4] Launching: am start -n %PROJECTIVY_ACTIVITY% >>"%LOGFILE%"
"%ADB%" %TARGET% shell am start -n %PROJECTIVY_ACTIVITY% >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"Error" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [!!] Launch failed, trying alternative method...
    echo [STEP 4] Direct launch failed, trying monkey... >>"%LOGFILE%"
    :: Try launching via monkey (simulates app open from launcher)
    "%ADB%" %TARGET% shell monkey -p %PROJECTIVY_PKG% -c android.intent.category.LEANBACK_LAUNCHER 1 >"%TMPFILE%" 2>&1
    type "%TMPFILE%" >>"%LOGFILE%"
    findstr /C:"Events injected" "%TMPFILE%" >nul 2>&1
    if !errorlevel!==0 (
        echo   [OK] Projectivy launched via alternative method
    ) else (
        echo   [!!] Could not launch Projectivy automatically.
        echo   [!!] Please open it manually from your Fire TV app list.
    )
) else (
    echo   [OK] Projectivy launched
)

echo.
echo   +---------------------------------------------------------+
echo   ^|  ACTION REQUIRED on your Fire TV:                       ^|
echo   ^|                                                         ^|
echo   ^|  1. Projectivy should now be on your screen             ^|
echo   ^|  2. Go to Projectivy Settings (long-press center btn)   ^|
echo   ^|  3. Select 'General'                                    ^|
echo   ^|  4. Enable 'Override current launcher'                  ^|
echo   ^|                                                         ^|
echo   ^|  This makes the Home button open Projectivy instead     ^|
echo   ^|  of the Amazon launcher.                                ^|
echo   +---------------------------------------------------------+
echo.
pause

:: ============================================================
:: STEP 5: Disable bloatware (with reboot retry for new unlocks)
:: ============================================================
set "TOTAL_DISABLED=0"
set "PASS=0"
set "BLOAT=com.amazon.tv.acr com.amazon.hybridadidservice com.amazon.client.metrics.api com.amazon.perfc com.amazon.perfcollection com.amazon.device.telemetry.emitter com.amazon.dp.logger com.amazon.wirelessmetrics.service com.amazon.shoptv.client com.amazon.shoptv.firetv.client com.amazon.venezia com.amazon.bueller.photos com.amazon.bueller.music com.amazon.imdb.tv.android.app com.amazon.minitv.android.app com.amazon.gamehub com.amazon.sneakpeek com.amazon.ftv.screensaver com.amazon.storm.lightning.tutorial com.amazon.tmm.tutorial com.amazon.tv.releasenotes com.amazon.audiohome com.amazon.tv.livetv com.amazon.device.rdmapplication com.amazon.logan com.amazon.fireos.cirruscloud com.amazon.ods.kindleconnect com.amazon.cloud9 com.amazon.tahoe com.amazon.aria com.amazon.hedwig com.amazon.whisperplay.service.install com.amazon.tv.support com.amazon.ceviche com.amazon.d3 com.amazon.tv.turnstile com.amazon.avls.experience com.amazon.smarthomemapviewapp com.amazon.tv.ftvambient com.amazon.tv.alexaalerts com.amazon.tv.alexanotifications com.amazon.wifilocker com.amazon.spiderpork com.amazon.tv.notificationcenter com.amazon.firebat com.amazon.ssm com.amazon.ssmsys com.amazon.tv.easyupgrade com.amazon.dpcclient com.amazon.sharingservice.android.client.proxy com.amazon.livedeviceservice com.amazon.prism.android.service com.amazon.privacypassservice com.amazon.tv.legal.notices com.amazon.rtcsessioncontroller"

:: Track packages we've already successfully disabled (across passes)
echo. >"%TMPFILE%.done"

:disable_loop
set /a "PASS+=1"
set "PASS_DISABLED=0"
set "PASS_PROTECTED=0"

echo.
echo   ========================================
echo     STEP 5: Disabling Bloatware (Pass !PASS!^)
echo   ========================================
echo [PASS !PASS!] Starting disable pass... >>"%LOGFILE%"

for %%p in (%BLOAT%) do (
    :: Skip if we already disabled this in a previous pass
    findstr /C:"%%p" "%TMPFILE%.done" >nul 2>&1
    if !errorlevel! neq 0 (
        echo [PASS !PASS!] Trying %%p... >>"%LOGFILE%"
        "%ADB%" %TARGET% shell pm disable-user --user 0 %%p >"%TMPFILE%" 2>&1
        type "%TMPFILE%" >>"%LOGFILE%"
        findstr /C:"disabled-user" "%TMPFILE%" >nul 2>&1
        if !errorlevel!==0 (
            echo   [OK] Disabled: %%p
            echo [DISABLED] %%p >>"%LOGFILE%"
            echo %%p>>"%TMPFILE%.done"
            set /a "PASS_DISABLED+=1"
            set /a "TOTAL_DISABLED+=1"
        ) else (
            findstr /C:"SecurityException" "%TMPFILE%" >nul 2>&1
            if !errorlevel!==0 (
                echo   [--] Protected: %%p
                echo [PROTECTED] %%p >>"%LOGFILE%"
                set /a "PASS_PROTECTED+=1"
            ) else (
                echo   [--] Skipped: %%p (not found on device^)
                echo [NOTFOUND] %%p >>"%LOGFILE%"
                echo %%p>>"%TMPFILE%.done"
            )
        )
    )
)

echo.
echo   Pass !PASS!: Disabled !PASS_DISABLED!, Protected !PASS_PROTECTED!
echo [PASS !PASS!] Disabled=!PASS_DISABLED! Protected=!PASS_PROTECTED! >>"%LOGFILE%"

:: Only reboot if we disabled NEW packages AND there are still protected ones to retry
if !PASS_DISABLED! GTR 0 if !PASS_PROTECTED! GTR 0 if !PASS! LSS 3 (
    echo.
    echo   [..] Some packages protected - rebooting to retry...
    "%ADB%" %TARGET% shell reboot >nul 2>&1
    echo   [..] Waiting 35 seconds...
    timeout /t 35 /nobreak >nul

    set "RECONNECTED=0"
    for /L %%i in (1,1,20) do (
        if !RECONNECTED!==0 (
            "%ADB%" connect %FIRE_IP%:5555 >nul 2>&1
            "%ADB%" %TARGET% shell echo ok >"%TMPFILE%" 2>&1
            findstr /C:"ok" "%TMPFILE%" >nul 2>&1
            if !errorlevel!==0 (
                timeout /t 5 /nobreak >nul
                set "RECONNECTED=1"
                echo   [OK] Device is back online
            ) else (
                echo   [..] Waiting for reboot... (%%i/20^)
                timeout /t 3 /nobreak >nul
            )
        )
    )

    if !RECONNECTED!==1 goto :disable_loop
    echo   [!!] Could not reconnect. Continuing with what we have...
)

:: Final reboot to apply all changes (skip if we already rebooted between passes)
if !PASS! GTR 1 goto :skip_final_reboot
echo.
echo   [..] Rebooting to apply changes...
"%ADB%" %TARGET% shell reboot >nul 2>&1
echo   [..] Waiting 35 seconds...
timeout /t 35 /nobreak >nul

set "RECONNECTED=0"
for /L %%i in (1,1,20) do (
    if !RECONNECTED!==0 (
        "%ADB%" connect %FIRE_IP%:5555 >nul 2>&1
        "%ADB%" %TARGET% shell echo ok >"%TMPFILE%" 2>&1
        findstr /C:"ok" "%TMPFILE%" >nul 2>&1
        if !errorlevel!==0 (
            timeout /t 5 /nobreak >nul
            set "RECONNECTED=1"
            echo   [OK] Device is back online
        ) else (
            echo   [..] Waiting for reboot... (%%i/20^)
            timeout /t 3 /nobreak >nul
        )
    )
)

if !RECONNECTED!==0 (
    echo   [!!] Could not reconnect after reboot.
    goto :fail
)

:: Re-disable anything Amazon re-enabled during reboot
echo.
echo   [..] Re-applying disabled packages after reboot...
set "REAPPLIED=0"
"%ADB%" %TARGET% shell pm list packages -d >"%TMPFILE%.disabled" 2>&1
for %%p in (%BLOAT%) do (
    findstr /C:"%%p" "%TMPFILE%.done" >nul 2>&1
    if !errorlevel!==0 (
        findstr /C:"package:%%p" "%TMPFILE%.disabled" >nul 2>&1
        if !errorlevel! neq 0 (
            "%ADB%" %TARGET% shell pm disable-user --user 0 %%p >nul 2>&1
            set /a "REAPPLIED+=1"
        )
    )
)
if !REAPPLIED! GTR 0 (
    echo   [OK] Re-disabled !REAPPLIED! packages that Amazon re-enabled
) else (
    echo   [OK] All packages stayed disabled after reboot
)

:skip_final_reboot

:: Re-disable anything Amazon re-enabled during the last reboot (for multi-pass)
if !PASS! GTR 1 (
    echo.
    echo   [..] Verifying packages are still disabled...
    set "REAPPLIED2=0"
    "%ADB%" %TARGET% shell pm list packages -d >"%TMPFILE%.disabled" 2>&1
    for %%p in (%BLOAT%) do (
        findstr /C:"%%p" "%TMPFILE%.done" >nul 2>&1
        if !errorlevel!==0 (
            findstr /C:"package:%%p" "%TMPFILE%.disabled" >nul 2>&1
            if !errorlevel! neq 0 (
                "%ADB%" %TARGET% shell pm disable-user --user 0 %%p >nul 2>&1
                set /a "REAPPLIED2+=1"
            )
        )
    )
    if !REAPPLIED2! GTR 0 (
        echo   [OK] Re-disabled !REAPPLIED2! packages that Amazon re-enabled
    ) else (
        echo   [OK] All packages stayed disabled after reboot
    )
)

:: ============================================================
:: STEP 6: Verify
:: ============================================================
echo.
echo   ========================================
echo     STEP 6: Verifying Persistence
echo   ========================================

:: Check Projectivy installed
"%ADB%" %TARGET% shell pm list packages >"%TMPFILE%" 2>&1
findstr /C:"%PROJECTIVY_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Projectivy is installed
) else (
    echo   [!!] Projectivy is NOT installed
)

:: Check accessibility
"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services >"%TMPFILE%" 2>&1
findstr /C:"%PROJECTIVY_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Accessibility service is active
) else (
    echo   [!!] Accessibility service is NOT active
)

:: Count disabled packages
set "DISABLED_COUNT=0"
"%ADB%" %TARGET% shell pm list packages -d >"%TMPFILE%" 2>&1
for /f %%a in ('type "%TMPFILE%" ^| find /c "package:"') do set "DISABLED_COUNT=%%a"
echo   [OK] !DISABLED_COUNT! packages remain disabled

:: ============================================================
:: RAM COMPARISON: Before vs After
:: ============================================================
echo.
echo   ========================================
echo     RAM Usage: Before vs After Cleanup
echo   ========================================

set "RAM_AFTER_TOTAL=0"
set "RAM_AFTER_AVAIL=0"
set "RAM_AFTER_USED=0"
set "PROCS_AFTER=0"

"%ADB%" %TARGET% shell "cat /proc/meminfo | grep MemTotal" >"%TMPFILE%" 2>&1
for /f "tokens=2" %%a in ('type "%TMPFILE%" 2^>nul') do set /a "RAM_AFTER_TOTAL=%%a / 1024"

"%ADB%" %TARGET% shell "cat /proc/meminfo | grep MemAvailable" >"%TMPFILE%" 2>&1
for /f "tokens=2" %%a in ('type "%TMPFILE%" 2^>nul') do set /a "RAM_AFTER_AVAIL=%%a / 1024"

set /a "RAM_AFTER_USED=RAM_AFTER_TOTAL - RAM_AFTER_AVAIL"

"%ADB%" %TARGET% shell "ps -A | grep com.amazon | wc -l" >"%TMPFILE%" 2>&1
for /f "tokens=1" %%a in ('type "%TMPFILE%" 2^>nul') do set "PROCS_AFTER=%%a"

set /a "RAM_FREED=RAM_AFTER_AVAIL - RAM_BEFORE_AVAIL"
set /a "PROCS_KILLED=PROCS_BEFORE - PROCS_AFTER"

echo.
echo                        BEFORE       AFTER       CHANGE
echo   ---------------------------------------------------------
echo   Available RAM:    !RAM_BEFORE_AVAIL! MB      !RAM_AFTER_AVAIL! MB      +!RAM_FREED! MB freed
echo   Used RAM:         !RAM_BEFORE_USED! MB      !RAM_AFTER_USED! MB
echo   Amazon processes: !PROCS_BEFORE!             !PROCS_AFTER!             -!PROCS_KILLED! removed
echo   ---------------------------------------------------------
echo.

echo.
echo   ========================================
echo     ALL DONE - Firestick Cleanup Complete!
echo   ========================================
echo.
echo   Projectivy Launcher is installed and configured.
echo   !TOTAL_DISABLED! bloatware packages disabled.
echo   !RAM_FREED! MB of RAM freed.
echo.
echo   To revert all changes, run:
echo     %~nx0 --revert
echo.
echo   Full log saved to: %LOGFILE%
echo.

:: Cleanup temp files and downloaded APK
del "%TMPFILE%" >nul 2>&1
del "%TMPFILE%.disabled" >nul 2>&1
del "%TMPFILE%.done" >nul 2>&1
del "%APK_DIR%ProjectivyLauncher-latest.apk" >nul 2>&1
pause
goto :done

:: ============================================================
:: REVERT MODE
:: ============================================================
:revert
echo.
echo   ========================================
echo     REVERTING ALL CHANGES
echo   ========================================
echo.

if not exist "%ADB%" (
    echo   [!!] ADB not found at: %ADB%
    goto :fail
)

set /p "FIRE_IP=  Enter your Fire TV IP address (e.g. 10.0.0.20): "
if "%FIRE_IP%"=="" (
    echo   [!!] No IP provided.
    goto :fail
)

set "TARGET=-s %FIRE_IP%:5555"

"%ADB%" connect %FIRE_IP%:5555 >nul 2>&1

echo.
echo   A connection request has been sent to your Fire TV.
echo   On your TV screen, select 'Always allow from this computer' and press OK.
echo.
pause

"%ADB%" connect %FIRE_IP%:5555 >nul 2>&1
timeout /t 2 /nobreak >nul

"%ADB%" %TARGET% shell echo ok >"%TMPFILE%" 2>&1
findstr /C:"ok" "%TMPFILE%" >nul 2>&1
if !errorlevel! neq 0 (
    echo   [!!] Could not connect to Fire TV.
    goto :fail
)
echo   [OK] Connected

:: Re-enable all disabled packages
echo   [..] Re-enabling disabled packages...
"%ADB%" %TARGET% shell pm list packages -d >"%TMPFILE%" 2>&1
for /f "tokens=2 delims=:" %%p in ('type "%TMPFILE%" 2^>nul') do (
    "%ADB%" %TARGET% shell pm enable %%p >nul 2>&1
    echo   [OK] Enabled: %%p
)

:: Remove accessibility service
"%ADB%" %TARGET% shell settings put secure enabled_accessibility_services "" >nul 2>&1
"%ADB%" %TARGET% shell settings put secure accessibility_enabled 0 >nul 2>&1
echo   [OK] Accessibility service removed

:: Remove notification listener
"%ADB%" %TARGET% shell settings put secure enabled_notification_listeners "" >nul 2>&1
echo   [OK] Notification listener removed

:: Remove overlay permission
"%ADB%" %TARGET% shell appops set %PROJECTIVY_PKG% SYSTEM_ALERT_WINDOW deny >nul 2>&1
echo   [OK] Overlay permission revoked

:: Remove HOME role
"%ADB%" %TARGET% shell cmd role remove-role-holder android.app.role.HOME %PROJECTIVY_PKG% >nul 2>&1
echo   [OK] HOME role removed

:: Uninstall Projectivy
"%ADB%" %TARGET% shell pm uninstall %PROJECTIVY_PKG% >"%TMPFILE%" 2>&1
findstr /C:"Success" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Projectivy uninstalled
) else (
    echo   [!!] Could not uninstall Projectivy (may not be installed^)
)

echo.
echo   ========================================
echo     REVERT COMPLETE
echo   ========================================
echo.
del "%TMPFILE%" >nul 2>&1
del "%TMPFILE%.disabled" >nul 2>&1
del "%TMPFILE%.done" >nul 2>&1
pause
goto :done


:: ============================================================
:: FAILURE EXIT
:: ============================================================
:fail
echo.
echo   Script failed. See errors above.
echo.
del "%TMPFILE%" >nul 2>&1
del "%TMPFILE%.disabled" >nul 2>&1
del "%TMPFILE%.done" >nul 2>&1
pause
goto :done

:: ============================================================
:: END OF SCRIPT
:: ============================================================
:done
endlocal
exit
