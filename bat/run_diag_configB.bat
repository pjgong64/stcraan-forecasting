@echo off
rem ===========================================================================
rem  run_diag_configB.bat -- revision round 1, reviewer 2 M4 / R1.3.
rem  Refits ST-CRAAN Configuration B on the three EO-bearing arms
rem  (F+EO, F+SP+EO, EO+SPA) and records hidden-state variation, the fusion
rem  weight ratio and the neutralisation statistics on 2022.
rem  Output: factorial7_out\diag_configB\configB_diag.csv  (~3 hours)
rem  DO NOT CLICK INSIDE THIS WINDOW: a click pauses the program ("Select" mode).
rem  If the title bar says "Select", press Esc.
rem ===========================================================================
setlocal
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
echo ===== ST-CRAAN Configuration B: branch-health diagnostics =====
%RSCRIPT% 12_Factorial7_run_diag.R STCRAAN arms=F+EO,F+SP+EO,EO+SPA auto
%RSCRIPT% 12_Factorial7_run_diag.R STCRAAN arms=F+EO,F+SP+EO,EO+SPA auto
echo   Done. Tell Claude.
goto :done
:norscript
echo   Could not run Rscript.
:done
echo.
pause
endlocal
