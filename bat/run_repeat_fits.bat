@echo off
rem ===========================================================================
rem  run_repeat_fits.bat -- how much does the study move when you run it again?
rem
rem  Refits the same cells under different seeds, each into its own folder
rem  factorial7_out\repeat_seed<n>, so the spread across repeats can be measured.
rem  The published run and the first refit already count as two draws; this adds
rem  the rest.
rem
rem  The spread is NOT only seed variation. h2o's random forest across threads,
rem  xgboost's histogram tie-breaking and GPU training are none of them bitwise
rem  reproducible even at a fixed seed -- the first refit proved that. A repeat
rem  samples all of it at once, which is exactly the quantity wanted: how far
rem  does a number move when the study is run again.
rem
rem  Keep it to the three tabular families and four arms and this is cheap.
rem ===========================================================================
setlocal

rem --- Seeds. Any integers; three here plus the two runs already on disk give
rem     five draws, which is enough to quote a range.
set "SEEDS=101 202 303"

rem --- Arms. Only the ones the contrasts need. Names must match the arm column
rem     of factorial7_out\factorial7_results.csv exactly.
set "ARMS=F,F+EO,F+SP,F+SP+EO"

rem --- Families. The three tabular ones fit on CPU and carry the argument. Add
rem     MLP and STCRAAN only if there is GPU time; their spread is already known
rem     to be the largest, which is itself the finding.
set "FAMS=LR RF XGB"

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
echo ========= factorial7 -- repeat fits (refit noise) =========
echo folder  : %CD%
if not defined RSCRIPT goto :norscript
echo Rscript : %RSCRIPT%
%RSCRIPT% --version >nul 2>&1
if errorlevel 1 goto :norscript

if not exist "12_Factorial7_run.R"    goto :missing
if not exist "12_Factorial7_config.R" goto :missing
if not exist "12_Factorial7_report.R" goto :missing

rem  seed= arrives with the same patch set as alpha=. An older runner would
rem  ignore it and write every repeat to the same folder under the same seed,
rem  producing a spread of zero for a reason that has nothing to do with the data.
findstr /c:"repeat_seed" "12_Factorial7_run.R" >nul 2>&1
if errorlevel 1 goto :unpatched

if not exist "factorial7_out\factorial7_results.csv" goto :nobase

echo seeds   : %SEEDS%
echo arms    : %ARMS%
echo families: %FAMS%
echo output  : factorial7_out\repeat_seed*\
echo ===========================================================
echo.
echo   Each seed is a full fit of the families and arms above.
echo   Close this window now to cancel.
echo.
pause

for %%S in (%SEEDS%) do (
  echo.
  echo -----------------------------------------------------------
  echo   seed = %%S
  echo -----------------------------------------------------------
  %RSCRIPT% 12_Factorial7_run.R %FAMS% arms=%ARMS% seed=%%S auto redo
  if errorlevel 1 goto :failed
)

echo.
echo   Done. Next: run_refit_noise.bat, which reads the published run, the
echo   first refit and every repeat together and reports the spread.
goto :done

:failed
echo.
echo   *** stopped with an error on the seed above ***
echo   Seeds that finished are complete in their own folders. Fix the problem
echo   and run this again; finished cells are skipped within a folder.
goto :done

:unpatched
echo.
echo   This 12_Factorial7_run.R does not understand seed=.
echo   Replace it with the patched copy first. The old runner would write
echo   every repeat into the same folder at the same seed, and the spread
echo   would come out as zero for the wrong reason.
goto :done

:nobase
echo.
echo   factorial7_out\factorial7_results.csv is not there. Run the main refit
echo   first -- it is one of the draws the spread is measured over.
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