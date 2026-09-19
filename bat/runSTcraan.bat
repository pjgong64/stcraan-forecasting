@echo off
rem ===========================================================================
rem  run_stcraan.bat -- double-click to run the ST-CRAAN family only.
rem  Self-contained: no other .bat is invoked from here, so there is one
rem  console window and one pause at the end.
rem  Finished cells are skipped, so it picks up only the arms still missing.
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

echo.
echo ============== factorial7 -- ST-CRAAN ==============
echo folder  : %CD%
if not defined RSCRIPT goto :norscript
echo Rscript : %RSCRIPT%
%RSCRIPT% --version >nul 2>&1
if errorlevel 1 goto :norscript

if not exist "12_Factorial7_run.R"    goto :missing
if not exist "12_Factorial7_config.R" goto :missing
if not exist "12_Factorial7_report.R" goto :missing
if not exist "factorial7_out" mkdir "factorial7_out"

set "FAMS=STCRAAN"
echo families: %FAMS%
echo results : factorial7_out\factorial7_results.csv
echo log     : factorial7_out\factorial7_log.txt
echo ===============================================
echo.

%RSCRIPT% 12_Factorial7_run.R %FAMS% auto
if errorlevel 1 (
  echo.
  echo   *** the run stopped with an error ***
  echo   See the lines above and factorial7_out\factorial7_errors.log
  echo   Finished cells are saved -- run this .bat again to continue.
  goto :done
)

echo.
echo ---------------------- FINAL REPORT ----------------------
%RSCRIPT% 12_Factorial7_report.R
goto :done

:norscript
echo.
echo   Could not run Rscript.
echo   Open this .bat in Notepad and set the full path near the top:
echo     set "RSCRIPT="C:\Program Files\R\R-4.6.0\bin\x64\Rscript.exe""
echo   Use the same R that RStudio uses -- check with .libPaths() there.
goto :done

:missing
echo.
echo   An R file is missing. These three must sit next to this .bat:
echo     12_Factorial7_run.R  12_Factorial7_config.R  12_Factorial7_report.R
echo.
dir /b 12_Factorial7_*.R 2>nul

:done
echo.
pause
endlocal