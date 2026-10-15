@echo off
rem ===========================================================================
rem  run_fill_all.bat -- revision round 1: fill every empty cell of
rem  Table S6 and Table 10, and settle the ST-CRAAN +0.0254 of Table 10.
rem   A  grouped/OOF (test 2022) : MLP, ST-CRAAN on EO and SP          4 cells
rem   B  rolling 2020->2021      : MLP, ST-CRAAN on EO and SP          4 cells
rem   C  rolling + neutralisation: ST-CRAAN F+SP+EO                    1 cell
rem   D  rolling, seeds 101/202/303: ST-CRAAN F+SP and F+SP+EO         6 cells
rem  About 11-12 hours in total. Finished cells are skipped on restart.
rem  2022 is never used to fit; in B, C and D it is not read at all.
rem  Log: factorial7_out\fill_all_log.txt
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
set "FLOG=factorial7_out\fill_all_log.txt"
if not defined RSCRIPT goto :norscript
%RSCRIPT% --version >nul 2>&1
if errorlevel 1 goto :norscript
if not exist "12_Factorial7_run_grouped.R" goto :missing
if not exist "12_Factorial7_run_rolling.R" goto :missing
if not exist "12_Factorial7_run_rolling_diag.R" goto :missing

echo ===== revision R1 -- fill all empty cells (about 11-12 hours) =====
call :log START
echo --- A: grouped/OOF, MLP and ST-CRAAN on EO and SP
%RSCRIPT% 12_Factorial7_run_grouped.R MLP STCRAAN arms=EO,SP auto
call :log A done
echo --- B: rolling 2020-2021, MLP and ST-CRAAN on EO and SP
%RSCRIPT% 12_Factorial7_run_rolling.R MLP STCRAAN arms=EO,SP auto
call :log B done
echo --- C: rolling 2020-2021 with neutralisation, ST-CRAAN F+SP+EO
%RSCRIPT% 12_Factorial7_run_rolling_diag.R STCRAAN arms=F+SP+EO auto
call :log C done
echo --- D: rolling 2020-2021, ST-CRAAN F+SP and F+SP+EO, seeds 101 202 303
for %%S in (101 202 303) do (
  %RSCRIPT% 12_Factorial7_run_rolling.R STCRAAN arms=F+SP,F+SP+EO seed=%%S auto
  call :log D seed %%S done
)
call :log ALL DONE
echo   Done. Tell Claude.
goto :done

:log
echo [%date% %time%] %* >> "%FLOG%"
goto :eof

:missing
echo   A script is missing. Put 12_Factorial7_run_rolling_diag.R next to this file
echo   and next to 12_Factorial7_run_grouped.R / 12_Factorial7_run_rolling.R.
goto :done
:norscript
echo   Could not run Rscript.
:done
echo.
pause
endlocal
