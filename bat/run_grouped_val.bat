@echo off
rem ===========================================================================
rem  run_grouped_val.bat -- revision round 1 (reviewer 2, M3c).
rem  Refits the whole factorial with the early-stopping split drawn by BORROWER
rem  (12_Factorial7_run_grouped.R),
rem  with out-of-fold target encodings for the development rows, into factorial7_out\grouped_val_oof\.
rem  It first WAITS until run_repeat_deep.bat has written "ALL DONE" to its log,
rem  so it can be started now and will queue behind the seed runs.
rem  Tabular families first (CPU, ~2 h), then MLP and ST-CRAAN (~12 h).
rem  Safe to stop and restart: finished cells are skipped.
rem ===========================================================================
setlocal
set "LOG=factorial7_out\repeat_deep_log.txt"
set "GLOG=factorial7_out\grouped_val_log.txt"

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
if not exist "12_Factorial7_run_grouped.R" goto :missing

echo.
echo ===== revision R1 -- borrower-grouped validation split =====
echo   Waiting for the seed runs to finish (checks every 10 minutes).
echo   Close this window to cancel.

:wait
if not exist "%LOG%" goto :sleep
findstr /c:"ALL DONE" "%LOG%" >nul 2>&1
if not errorlevel 1 goto :go
:sleep
timeout /t 600 /nobreak >nul
goto :wait

:go
call :log grouped START
%RSCRIPT% 12_Factorial7_run_grouped.R LR RF XGB auto
%RSCRIPT% 12_Factorial7_run_grouped.R LR RF XGB auto
call :log grouped tabular done
%RSCRIPT% 12_Factorial7_run_grouped.R MLP STCRAAN arms=F,F+EO,F+SP,F+SP+EO,SPA,EO+SPA auto
%RSCRIPT% 12_Factorial7_run_grouped.R MLP STCRAAN arms=F,F+EO,F+SP,F+SP+EO,SPA,EO+SPA auto
call :log grouped ALL DONE
echo   Done. Tell Claude; results are in factorial7_out\grouped_val_oof\
goto :done

:log
echo [%date% %time%] %*
echo [%date% %time%] %*>> "%GLOG%"
goto :eof

:norscript
echo   Could not run Rscript. Set the full path on the line: set "RSCRIPT=
goto :done
:missing
echo   12_Factorial7_run_grouped.R must sit next to this file.
:done
echo.
pause
endlocal
