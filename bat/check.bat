@echo off
rem ===========================================================================
rem  check_setup.bat  --  prints what this machine actually has. Runs nothing
rem  heavy. Send the output if run_factorial7.bat misbehaves.
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
echo ===================== SETUP CHECK =====================
echo.
echo [1] folder
echo     %CD%
echo.
echo [2] factorial7 files here
dir /b 12_Factorial7_*.R 2>nul
echo.
echo [3] data file
if exist "data_hybrid2_prec_sai.txt" (echo     data_hybrid2_prec_sai.txt   FOUND) else (echo     data_hybrid2_prec_sai.txt   *** NOT HERE ***)
echo.
echo [4] results
if exist "factorial7_out\factorial7_results.csv" (echo     results file exists -- finished cells will be skipped) else (echo     no results yet)
echo.
echo [5] Rscript
if not defined RSCRIPT (
  echo     *** not found. Pin it at the top of both .bat files. ***
  goto :end
)
echo     %RSCRIPT%
%RSCRIPT% --version 2>&1
echo.
echo [6] R version and library paths   ^(must match RStudio^)
%RSCRIPT% -e "cat('   ', R.version.string, '\n'); for (p in .libPaths()) cat('    lib:', p, '\n')"
echo.
echo [7] R packages
%RSCRIPT% -e "for (p in c('data.table','h2o','xgboost','keras','tensorflow','reticulate')) { inst <- p %%in%% rownames(installed.packages()); msg <- if (!inst) '*** NOT INSTALLED ***' else { e <- tryCatch({loadNamespace(p); NA_character_}, error=function(e) conditionMessage(e)); if (is.na(e)) paste('ok  ', dirname(find.package(p))) else paste('*** INSTALLED BUT FAILS TO LOAD:', substr(gsub('[\r\n]+',' ',e),1,90)) }; cat(sprintf('    %%-12s %%s\n', p, msg)) }"
echo.
echo [8] config file version
rem  The python search lives in the config. If this .bat is newer than the
rem  config sitting beside it, [9] and [10] cannot work -- and the symptom,
rem  "could not find function conda_envs", names the function rather than the
rem  stale file, which sends you looking in the wrong place.
%RSCRIPT% -e "source('12_Factorial7_config.R'); v <- if (is.null(CFG$config_version)) '(older than 2026-09-15b)' else CFG$config_version; cat('    12_Factorial7_config.R :', v, '\n'); if (!exists('conda_envs')) { cat('\n    *** This config is an OLD copy. Replace 12_Factorial7_config.R\n'); cat('        with the one sent alongside this .bat, then run again.\n'); cat('        Steps [9] and [10] are skipped until then. ***\n') }"
echo.
echo [9] Python environments on disk
rem  Read off the filesystem, not from conda. "Unable to find conda binary" only
rem  means conda.exe is not on PATH in this window -- the environments are still
rem  there, and the runner reaches them by path.
%RSCRIPT% -e "source('12_Factorial7_config.R'); if (!exists('conda_envs')) quit(save='no'); e <- conda_envs(); if (is.null(e)) cat('    none found under the usual install roots\n') else for (i in seq_len(nrow(e))) cat(sprintf('    %%-3s %%-22s %%s\n', if (e$has_tf[i]) 'tf' else '', e$name[i], e$python[i]))"
echo.
echo [10] Python that keras will use
%RSCRIPT% -e "source('12_Factorial7_config.R'); cat('    CFG$python_env =', CFG$python_env, '\n'); if (!exists('find_conda_python')) quit(save='no'); p <- find_conda_python(CFG$python_env); if (is.na(p)) { cat('    *** that name/path does not resolve to a python.exe. Copy one of\n'); cat('        the paths from [9] into CFG$python_env in the config. ***\n') } else { cat('    resolves to    =', p, '\n'); try({ reticulate::use_python(p, required=TRUE); cat('    tensorflow     =', if (reticulate::py_module_available('tensorflow')) 'available' else '*** NOT importable ***', '\n') }) }"

:end
echo.
echo =======================================================
echo.
pause
endlocal