@echo off
setlocal enabledelayedexpansion
title Firestick Cleanup Tool
color 0A

set "ADB=%~dp0adb\adb.exe"
set "APK_DIR=%~dp0"
set "AT4K_PKG=com.overdevs.at4k"
set "AT4K_ACTIVITY=%AT4K_PKG%/.MainActivity"
set "AT4K_ACCESSIBILITY=%AT4K_PKG%/.Hra"
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
echo         AT4K Launcher + Debloat
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
:: STEP 2: Locate or install AT4K
:: ============================================================
echo.
echo   ========================================
echo     STEP 2: Installing AT4K Launcher
echo   ========================================

:: Check if an APK already exists
set "APK_FILE="
for %%f in ("%APK_DIR%AT4K*.apk" "%APK_DIR%base.apk") do (
    if not defined APK_FILE set "APK_FILE=%%f"
)

if defined APK_FILE (
    echo   [OK] APK found: !APK_FILE!
    goto :install
)

echo   [!!] No AT4K APK file found in: %APK_DIR%
echo.
echo   Please place one of the following files in the script directory:
echo     - AT4K.apk
echo     - AT4K_0.99.apk
echo     - base.apk
echo.
echo   You can download AT4K from: https://at4k.com/
echo.
pause
goto :fail

:: ============================================================
:: STEP 3: Install AT4K
:: ============================================================
:install
echo.
echo   ========================================
echo     STEP 3: Installing AT4K Launcher
echo   ========================================

:: Check if already installed
echo   [..] Checking for existing installation...
"%ADB%" %TARGET% shell pm path %AT4K_PKG% >"%TMPFILE%" 2>&1
findstr /C:"package:" "%TMPFILE%" >nul 2>&1

if !errorlevel!==0 (
    echo   [OK] AT4K is already installed.
    choice /C YN /M "  Reinstall AT4K"
    if errorlevel 2 goto :configure
)

echo   [..] Pushing APK to device...
echo [STEP 3] Pushing APK: !APK_FILE! >>"%LOGFILE%"
"%ADB%" %TARGET% push "!APK_FILE!" /data/local/tmp/AT4K.apk >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"pushed" "%TMPFILE%" >nul 2>&1
if !errorlevel! neq 0 (
    echo   [!!] Failed to push APK to device.
    type "%TMPFILE%"
    goto :fail
)
echo   [OK] APK pushed to device

echo   [..] Installing...
echo [STEP 3] Running: pm install -r /data/local/tmp/AT4K.apk >>"%LOGFILE%"
"%ADB%" %TARGET% shell pm install -r /data/local/tmp/AT4K.apk >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"Success" "%TMPFILE%" >nul 2>&1
if !errorlevel! neq 0 (
    echo   [!!] Install failed.
    type "%TMPFILE%"
    goto :fail
)

:: Verify the package actually exists on device
echo [STEP 3] Verifying package path... >>"%LOGFILE%"
"%ADB%" %TARGET% shell pm path %AT4K_PKG% >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"package:" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] AT4K Launcher installed and verified
) else (
    echo   [!!] Install reported success but package not found on device.
    goto :fail
)

:: Clean up temp APK on device
"%ADB%" %TARGET% shell rm /data/local/tmp/AT4K.apk >nul 2>&1

:: ============================================================
:: STEP 4: Configure as default launcher
:: ============================================================
:configure
echo.
echo   ========================================
echo     STEP 4: Configuring AT4K
echo   ========================================

:: Enable accessibility service
echo [STEP 4] Setting accessibility service... >>"%LOGFILE%"
"%ADB%" %TARGET% shell settings put secure enabled_accessibility_services %AT4K_ACCESSIBILITY% >>"%LOGFILE%" 2>&1
"%ADB%" %TARGET% shell settings put secure accessibility_enabled 1 >>"%LOGFILE%" 2>&1

:: Verify
"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"%AT4K_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Accessibility service enabled
) else (
    echo   [!!] Could not enable accessibility service
    goto :fail
)

:: CRITICAL: Disable Amazon's default launcher COMPLETELY
echo [STEP 4] Disabling Amazon launchers... >>"%LOGFILE%"
"%ADB%" %TARGET% shell pm disable-user --user 0 com.amazon.tv.launcher >>"%LOGFILE%" 2>&1
"%ADB%" %TARGET% shell pm disable-user --user 0 com.amazon.tv.selectivepause >>"%LOGFILE%" 2>&1
"%ADB%" %TARGET% shell pm hide --user 0 com.amazon.tv.launcher >>"%LOGFILE%" 2>&1
echo   [OK] Amazon launchers disabled

:: Remove any existing HOME role holders
echo [STEP 4] Clearing existing HOME roles... >>"%LOGFILE%"
"%ADB%" %TARGET% shell cmd role remove-role-holder android.app.role.HOME com.amazon.tv.launcher >>"%LOGFILE%" 2>&1
"%ADB%" %TARGET% shell cmd role remove-role-holder android.app.role.HOME com.amazon.tv.selectivepause >>"%LOGFILE%" 2>&1

:: Set AT4K as HOME role
echo [STEP 4] Setting HOME role... >>"%LOGFILE%"
"%ADB%" %TARGET% shell cmd role add-role-holder android.app.role.HOME %AT4K_PKG% >>"%LOGFILE%" 2>&1
echo   [OK] HOME role assigned to AT4K

:: Set as default LEANBACK launcher
echo [STEP 4] Setting as default LEANBACK launcher... >>"%LOGFILE%"
"%ADB%" %TARGET% shell cmd package set-default-home --user 0 %AT4K_PKG%/.MainActivity >>"%LOGFILE%" 2>&1

:: Launch it
echo [STEP 4] Launching: am start -n %AT4K_ACTIVITY% >>"%LOGFILE%"
"%ADB%" %TARGET% shell am start -n %AT4K_ACTIVITY% >"%TMPFILE%" 2>&1
type "%TMPFILE%" >>"%LOGFILE%"
findstr /C:"Error" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [!!] Launch failed, trying alternative method...
    echo [STEP 4] Direct launch failed, trying monkey... >>"%LOGFILE%"
    :: Try launching via monkey (simulates app open from launcher)
    "%ADB%" %TARGET% shell monkey -p %AT4K_PKG% -c android.intent.category.LEANBACK_LAUNCHER 1 >"%TMPFILE%" 2>&1
    type "%TMPFILE%" >>"%LOGFILE%"
    findstr /C:"Events injected" "%TMPFILE%" >nul 2>&1
    if !errorlevel!==0 (
        echo   [OK] AT4K launched via alternative method
    ) else (
        echo   [!!] Could not launch AT4K automatically.
        echo   [!!] Please open it manually from your Fire TV app list.
    )
) else (
    echo   [OK] AT4K launched
)

echo.
echo   +---------------------------------------------------------+
echo   ^|  ACTION REQUIRED on your Fire TV:                       ^|
echo   ^|                                                         ^|
echo   ^|  1. AT4K should now be on your screen                   ^|
echo   ^|  2. Grant any requested permissions                     ^|
echo   ^|  3. Configure AT4K as needed                            ^|
echo   ^|                                                         ^|
echo   ^|  AT4K is now set as your Home launcher. The Home button ^|
echo   ^|  will open AT4K. Amazon launcher has been disabled.     ^|
echo   +---------------------------------------------------------+
echo.
pause

:: ============================================================
:: STEP 5: Optional apps — ask user what to keep
:: ============================================================
echo.
echo   ========================================
echo     STEP 5: Choose What to Disable
echo   ========================================
echo.
echo   The following Amazon apps can be disabled. Some you may
echo   actually use — answer Y/N for each one.
echo   (Tracking, telemetry, and bloat are always disabled.)
echo.

set "OPTIONAL_BLOAT="

:: Amazon Video Services (DRM/playback — breaks Prime Video if disabled)
echo   Note: answer N to the next question if you use Prime Video,
echo         Freevee, or MiniTV — disabling these breaks playback.
set /p "OPT_VIDEO=  Disable Amazon Video services?         (Y/N): "
if /i "!OPT_VIDEO!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.avls.experience com.amazon.prism.android.service com.amazon.dp.logger com.amazon.livedeviceservice com.amazon.rtcsessionco"

:: Amazon Appstore
set /p "OPT_APPSTORE=  Disable Amazon Appstore?              (Y/N): "
if /i "!OPT_APPSTORE!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.venezia"

:: Amazon Photos
set /p "OPT_PHOTOS=  Disable Amazon Photos?                 (Y/N): "
if /i "!OPT_PHOTOS!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.bueller.photos"

:: Amazon Music
set /p "OPT_MUSIC=  Disable Amazon Music?                  (Y/N): "
if /i "!OPT_MUSIC!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.bueller.music"

:: Freevee / IMDb TV
set /p "OPT_FREEVEE=  Disable Freevee / IMDb TV?              (Y/N): "
if /i "!OPT_FREEVEE!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.imdb.tv.android.app"

:: MiniTV
set /p "OPT_MINITV=  Disable Amazon MiniTV?                 (Y/N): "
if /i "!OPT_MINITV!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.minitv.android.app"

:: Game Hub
set /p "OPT_GAMES=  Disable Amazon Game Hub?               (Y/N): "
if /i "!OPT_GAMES!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.gamehub"

:: Live TV
set /p "OPT_LIVETV=  Disable Amazon Live TV?                (Y/N): "
if /i "!OPT_LIVETV!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.tv.livetv"

:: Alexa Voice Features
set /p "OPT_ALEXA=  Disable Alexa alerts/notifications?    (Y/N): "
if /i "!OPT_ALEXA!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.tv.alexaalerts com.amazon.tv.alexanotifications com.amazon.audiohome"

:: Silk Browser
set /p "OPT_SILK=  Disable Silk Browser (Amazon Cloud9)?  (Y/N): "
if /i "!OPT_SILK!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.cloud9"

:: Smart Home
set /p "OPT_SMARTHOME=  Disable Smart Home features?            (Y/N): "
if /i "!OPT_SMARTHOME!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.smarthomemapviewapp"

:: WhisperPlay (casting)
set /p "OPT_CAST=  Disable WhisperPlay (casting)?         (Y/N): "
if /i "!OPT_CAST!"=="Y" set "OPTIONAL_BLOAT=!OPTIONAL_BLOAT! com.amazon.whisperplay.service.install"

echo.
echo   [OK] Preferences saved. All tracking/telemetry/bloat will
echo        always be disabled regardless of choices above.
echo.

:: ============================================================
:: STEP 6: Disable bloatware (with reboot retry for new unlocks)
:: ============================================================

:: Always-disable list: tracking, telemetry, shopping, and background junk
:: NOTE: com.amazon.tv.settings is KEPT ENABLED for access to Fire TV settings
set "BLOAT=com.amazon.tv.acr com.amazon.hybridadidservice com.amazon.perfc com.amazon.perfcollection com.amazon.device.telemetry.emitter com.amazon.wirelessmetrics.service com.amazon.shoptv.client com.amazon.shoptv.firetv.client com.amazon.sneakpeek com.amazon.ftv.screensaver com.amazon.storm.lightning.tutorial com.amazon.tmm.tutorial com.amazon.tv.releasenotes com.amazon.fireos.cirruscloud com.amazon.device.rdmapplication com.amazon.aria com.amazon.hedwig com.amazon.logan com.amazon.tv.support com.amazon.tv.turnstile com.amazon.tv.ftvambient com.amazon.notificationcenter com.amazon.privacypassservice com.amazon.device.update.service com.amazon.fvp.update.service"

:: Append user's optional choices
set "BLOAT=!BLOAT! !OPTIONAL_BLOAT!"

:: Track packages we've already successfully disabled (across passes)
echo. >"%TMPFILE%.done"

:disable_loop
set /a "PASS+=1"
set "PASS_DISABLED=0"
set "PASS_PROTECTED=0"

echo.
echo   ========================================
echo     STEP 6: Disabling Bloatware (Pass !PASS!^)
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
:: STEP 7: Verify
:: ============================================================
echo.
echo   ========================================
echo     STEP 7: Verifying Persistence
echo   ========================================

:: Check AT4K installed
"%ADB%" %TARGET% shell pm list packages >"%TMPFILE%" 2>&1
findstr /C:"%AT4K_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] AT4K is installed
) else (
    echo   [!!] AT4K is NOT installed
)

:: Check accessibility
"%ADB%" %TARGET% shell settings get secure enabled_accessibility_services >"%TMPFILE%" 2>&1
findstr /C:"%AT4K_PKG%" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Accessibility service is active
) else (
    echo   [!!] Accessibility service is NOT active
)

:: Check Amazon launcher is disabled
"%ADB%" %TARGET% shell pm list packages -d >"%TMPFILE%" 2>&1
findstr /C:"com.amazon.tv.launcher" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Amazon launcher is disabled
) else (
    echo   [!!] Amazon launcher is NOT disabled
)

:: Check Fire TV Settings is still enabled
"%ADB%" %TARGET% shell pm list packages >"%TMPFILE%" 2>&1
findstr /C:"com.amazon.tv.settings" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] Fire TV Settings is available
) else (
    echo   [!!] Fire TV Settings not found
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
echo   AT4K Launcher is installed and configured.
echo   Amazon launcher has been DISABLED.
echo   Update services have been DISABLED.
echo   Fire TV Settings remain AVAILABLE.
echo   !TOTAL_DISABLED! bloatware packages disabled.
echo   !RAM_FREED! MB of RAM freed.
echo.
echo   ACCESSING FIRE TV SETTINGS:
echo   Press the Menu button on Fire TV and look for Settings.
echo   You can also use AT4K's Settings menu.
echo.
echo   To revert all changes, run:
echo     %~nx0 --revert
echo.
echo   Full log saved to: %LOGFILE%
echo.

:: Cleanup temp files
del "%TMPFILE%" >nul 2>&1
del "%TMPFILE%.disabled" >nul 2>&1
del "%TMPFILE%.done" >nul 2>&1
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

:: Re-enable Amazon launchers
echo   [..] Re-enabling Amazon launchers...
"%ADB%" %TARGET% shell pm enable com.amazon.tv.launcher >nul 2>&1
"%ADB%" %TARGET% shell pm enable com.amazon.tv.selectivepause >nul 2>&1
"%ADB%" %TARGET% shell pm unhide --user 0 com.amazon.tv.launcher >nul 2>&1
echo   [OK] Amazon launchers re-enabled

:: Re-enable Fire TV Settings
echo   [..] Re-enabling Fire TV Settings...
"%ADB%" %TARGET% shell pm enable com.amazon.tv.settings >nul 2>&1
echo   [OK] Fire TV Settings re-enabled

:: Remove accessibility service
"%ADB%" %TARGET% shell settings put secure enabled_accessibility_services "" >nul 2>&1
"%ADB%" %TARGET% shell settings put secure accessibility_enabled 0 >nul 2>&1
echo   [OK] Accessibility service removed

:: Remove HOME role
"%ADB%" %TARGET% shell cmd role remove-role-holder android.app.role.HOME %AT4K_PKG% >nul 2>&1
echo   [OK] HOME role removed

:: Uninstall AT4K
"%ADB%" %TARGET% shell pm uninstall %AT4K_PKG% >"%TMPFILE%" 2>&1
findstr /C:"Success" "%TMPFILE%" >nul 2>&1
if !errorlevel!==0 (
    echo   [OK] AT4K uninstalled
) else (
    echo   [!!] Could not uninstall AT4K (may not be installed^)
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
