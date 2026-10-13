@echo off
rem ===========================================================================
rem  run_after_grouped.bat -- revision round 1, reviewer 2: M4 and M3a.
rem  WAITS until run_grouped_val.bat has written "grouped ALL DONE", then runs:
rem    1. 13_R1_ablation_sim.R ablation  -- which revival change matters (~6 h)
rem    2. 13_R1_ablation_sim.R sim       -- diagnostics on a known signal (~1 h)
rem    3. 12_Factorial7_run_rolling.R    -- fit 2020, test 2021 (~7 h)
rem  Safe to stop and restart: finished pieces are skipped.
rem ===========================================================================
setlocal
set "GLOG=factorial7_out\grouped_val_log.txt"
set "ALOG=factorial7_out\after_grouped_log.txt"

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
if not exist "13_R1_ablation_sim.R" goto :missing
if not exist "12_Factorial7_run_rolling.R" goto :missing

echo.
echo ===== revision R1 -- ablation, simulation, rolling origin =====
echo   Waiting for run_grouped_val.bat to finish (checks every 10 minutes).
echo   Close this window to cancel.

:wait
if not exist "%GLOG%" goto :sleep
findstr /c:"grouped ALL DONE" "%GLOG%" >nul 2>&1
if not errorlevel 1 goto :go
:sleep
timeout /t 600 /nobreak >nul
goto :wait

:go
call :log START
%RSCRIPT% 13_R1_ablation_sim.R ablation
call :log ablation done
%RSCRIPT% 13_R1_ablation_sim.R sim
call :log sim done
%RSCRIPT% 12_Factorial7_run_rolling.R LR RF XGB auto
%RSCRIPT% 12_Factorial7_run_rolling.R MLP STCRAAN arms=F,F+EO,F+SP,F+SP+EO,SPA,EO+SPA auto
call :log ALL DONE
echo   Done. Tell Claude.
goto :done

:log
echo [%date% %time%] %*
echo [%date% %time%] %*>> "%ALOG%"
goto :eof

:norscript
echo   Could not run Rscript. Set the full path on the line: set "RSCRIPT=
goto :done
:missing
echo   13_R1_ablation_sim.R and 12_Factorial7_run_rolling.R must sit next to this file.
:done
echo.
pause
endlocal
