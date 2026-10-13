@echo off
rem ===========================================================================
rem  run_repeat_deep.bat -- revision round 1 (reviewer 2, M3): seed-to-seed
rem  variation of the two neural families (MLP, ST-CRAAN).
rem
rem  Refits under four further seeds, each into factorial7_out\repeat_seed<n>\
rem  (the folders that already hold the LR/RF/XGB repeats; finished cells are
rem  skipped, nothing is deleted).
rem    Phase 1 : arms F, F+EO, F+SP, F+SP+EO   ~24 h
rem    Phase 2 : arms SPA, EO+SPA              ~12 h
rem  Safe to stop and restart: rerun this file, finished cells are skipped.
rem  Each seed is called twice so a cell that failed (e.g. GPU out of memory)
rem  is retried once. 2022 is only scored, never used for fitting or tuning.
rem ===========================================================================
setlocal

set "SEEDS=101 202 303 404"
set "FAMS=MLP STCRAAN"
set "ARMS1=F,F+EO,F+SP,F+SP+EO"
set "ARMS2=SPA,EO+SPA"
set "LOG=factorial7_out\repeat_deep_log.txt"

rem --- Pinned to the R that RStudio reports via .libPaths(). If that exact file
rem     is not there, the automatic search below takes over.
set "RSCRIPT="C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe""
if not exist "C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe" set "RSCRIPT="

cd /d "%~dp0"

rem --------------------------------------------------------------------------
rem  Locate Rscript.exe. R's installer does not add itself to PATH by default,
rem  so "Rscript is not recognized" is the normal state on a fresh Windows box.
rem  Scan the install folders FIRST: "for /d" walks names in order so the last
rem  match wins, which is the highest version. Going to the registry first picks
rem  whichever R registered last, not the newest -- that can land on an old
rem  machine-wide 4.5 while RStudio is using 4.6, and then every package looks
rem  "not installed" because it is in win-library\4.6.
rem --------------------------------------------------------------------------
if defined RSCRIPT goto :haveR

for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\x64\Rscript.exe" set "RSCRIPT="%%D\bin\x64\Rscript.exe""
for /d %%D in ("%LOCALAPPDATA%\Programs\R\R-*") do if exist "%%D\bin\x64\Rscript.exe" set "RSCRIPT="%%D\bin\x64\Rscript.exe""
for /d %%D in ("%ProgramFiles(x86)%\R\R-*") do if exist "%%D\bin\x64\Rscript.exe" set "RSCRIPT="%%D\bin\x64\Rscript.exe""
for /d %%D in ("C:\R\R-*") do if exist "%%D\bin\x64\Rscript.exe" set "RSCRIPT="%%D\bin\x64\Rscript.exe""
if defined RSCRIPT goto :haveR

for /f "tokens=2,*" %%a in ('reg query "HKCU\SOFTWARE\R-core\R64" /v InstallPath 2^>nul') do set "RHOME=%%b"
if not defined RHOME for /f "tokens=2,*" %%a in ('reg query "HKLM\SOFTWARE\R-core\R64" /v InstallPath 2^>nul') do set "RHOME=%%b"
if defined RHOME if exist "%RHOME%\bin\x64\Rscript.exe" set "RSCRIPT="%RHOME%\bin\x64\Rscript.exe""
if defined RSCRIPT goto :haveR

where Rscript >nul 2>&1
if not errorlevel 1 set "RSCRIPT=Rscript"

:haveR

cd /d "%~dp0"
if not defined RSCRIPT goto :norscript
%RSCRIPT% --version >nul 2>&1
if errorlevel 1 goto :norscript
if not exist "12_Factorial7_run.R" goto :missing
findstr /c:"repeat_seed" "12_Factorial7_run.R" >nul 2>&1
if errorlevel 1 goto :missing
if not exist factorial7_out mkdir factorial7_out

echo.
echo ========= revision R1 -- neural repeat fits =========
echo folder  : %CD%
echo Rscript : %RSCRIPT%
echo seeds   : %SEEDS%
echo families: %FAMS%
echo phase 1 : %ARMS1%
echo phase 2 : %ARMS2%
echo log     : %LOG%
echo =====================================================
echo   Expect about 36 hours in total. Close this window now to cancel,
echo   or press a key to start. After that it runs unattended.
pause

call :log START
for %%S in (%SEEDS%) do call :one %%S "%ARMS1%" 1
for %%S in (%SEEDS%) do call :one %%S "%ARMS2%" 2
call :log ALL DONE
echo.
echo   Done. Tell Claude; the results are in factorial7_out\repeat_seed*\
goto :done

:one
rem  %1 = seed, %2 = quoted arm list, %3 = phase number
call :log phase %3 seed %1 start
%RSCRIPT% 12_Factorial7_run.R %FAMS% arms=%~2 seed=%1 auto
%RSCRIPT% 12_Factorial7_run.R %FAMS% arms=%~2 seed=%1 auto
call :log phase %3 seed %1 end
goto :eof

:log
echo [%date% %time%] %*
echo [%date% %time%] %*>> "%LOG%"
goto :eof

:norscript
echo.
echo   Could not run Rscript. Open this file in Notepad and set the full path
echo   on the line that starts with:  set "RSCRIPT=
goto :done

:missing
echo.
echo   12_Factorial7_run.R with seed= support must sit next to this file.

:done
echo.
pause
endlocal
