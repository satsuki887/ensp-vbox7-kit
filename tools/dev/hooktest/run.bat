@echo off
rem ============================================================================
rem  Concurrency test for the VBox52.dll CreateProcessW hook.
rem
rem  Builds build\selftest\VBox52.dll (adds the test-only ShimSelfTest export) and
rem  harness.exe, then for each AppCompat layer and thread count: 8 threads race
rem  to install the hooks, N threads spawn "modifyvm ... --uartmode2" lookalikes,
rem  and every child must have received "--uart2 0x2f8 3". Logs go to out\pd,
rem  not C:\ProgramData. Exit code 0 = all passed.
rem
rem    run.bat                 full matrix
rem    run.bat <dll>           test another build (e.g. an old shim built with
rem                            /DSHIM_SELFTEST) against the same matrix
rem ============================================================================
setlocal EnableDelayedExpansion
pushd "%~dp0"
set "DLL=%~f1"
if not defined DLL (
  call ..\..\..\build\build.bat selftest >nul || (echo [!] selftest build failed & popd & exit /b 1)
  set "DLL=%~dp0..\..\..\build\selftest\VBox52.dll"
)
call ..\vsenv.bat || (popd & exit /b 1)
if not exist out mkdir out
cl.exe /nologo /O2 /utf-8 /EHsc harness.cpp /Fo"out\\" /Fe"out\harness.exe" >nul || (echo [!] harness build failed & popd & exit /b 1)

set "ProgramData=%~dp0out\pd"
rem The shim creates only the last directory level, so the parent must exist.
if exist "%ProgramData%" rmdir /s /q "%ProgramData%"
mkdir "%ProgramData%"
set FAIL=0
for %%L in (none WIN7RTM) do (
  if "%%L"=="none" (set "__COMPAT_LAYER=") else (set "__COMPAT_LAYER=%%L")
  for %%C in ("1 20" "2 50" "16 25") do (
    if exist out\o rmdir /s /q out\o
    out\harness.exe "!DLL!" %%~C "%~dp0out\o" > out\last.txt 2>&1
    if errorlevel 1 (set FAIL=1 & set "R=FAIL") else (set "R=ok  ")
    for /f "tokens=*" %%r in ('findstr /c:"injected:" out\last.txt') do echo [!R!] layer=%%L threads/iters=%%~C  %%r
    findstr /c:"injected:" out\last.txt >nul || echo [FAIL] layer=%%L threads/iters=%%~C  harness crashed
  )
)
set "__COMPAT_LAYER="
for /f "tokens=3,* delims=]" %%a in ('findstr /c:"hooked via" "%ProgramData%\ensp-vbox-shim\vbox52_proxy.log"') do (echo hook path:%%a & goto :shown)
echo [!] no "hooked via" line in the shim log
:shown
popd
if %FAIL%==0 (echo ALL PASSED & exit /b 0) else (echo SOME FAILED & exit /b 1)
