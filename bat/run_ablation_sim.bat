@echo off
rem ===========================================================================
rem  run_ablation_sim.bat -- revision round 1, reviewer 2 M4 (re-run after a fix).
rem  WAITS until run_after_grouped.bat has written "ALL DONE" (rolling origin),
rem  then runs the ablation (~6 h) and the simulation (~1 h).
rem  Any R error is written to factorial7_out\r1_ablation_console.txt /
rem  r1_sim_console.txt.
rem ===========================================================================
setlocal
set "ALOG=factorial7_out\after_grouped_log.txt"
set "SLOG=factorial7_out\ablation_sim_log.txt"

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

echo ===== M4 ablation + simulation: waiting for the rolling-origin run =====
:wait
if not exist "%ALOG%" goto :sleep
findstr /c:"ALL DONE" "%ALOG%" >nul 2>&1
if not errorlevel 1 goto :go
:sleep
timeout /t 600 /nobreak >nul
goto :wait

:go
call :log START
%RSCRIPT% 13_R1_ablation_sim.R ablation
call :log ablation exit %errorlevel%
%RSCRIPT% 13_R1_ablation_sim.R sim
call :log sim exit %errorlevel%
call :log ALL DONE
echo   Done. Tell Claude.
goto :done

:log
echo [%date% %time%] %*
echo [%date% %time%] %*>> "%SLOG%"
goto :eof

:norscript
echo   Could not run Rscript.
:done
echo.
pause
endlocal
