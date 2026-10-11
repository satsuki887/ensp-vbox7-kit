@echo off
REM ============================================================================
REM  Build VBox52.dll  -- the eNSP <-> VirtualBox 7.x compatibility shim.
REM
REM  eNSP loads this DLL into the 32-bit eNSP_VBoxServer.exe, so it MUST be x86.
REM  The toolchain is found by ..\tools\dev\vsenv.bat (vswhere; set VCVARS to
REM  override; falls back to the Windows SDK NuGet packages in local\toolchain).
REM
REM    build.bat            release build  -> build\VBox52.dll
REM    build.bat selftest   + /DSHIM_SELFTEST test export -> build\selftest\VBox52.dll
REM                         (for tools\dev\hooktest; never ship this one)
REM
REM  /Brepro makes the output deterministic: the same toolchain produces the same
REM  bytes, so anyone can rebuild and compare against the committed DLL.
REM  Copy a release build to installer\payload\ and update DLL_SHA256 in
REM  installer\install.ps1 (move the old hash into PREV_DLL_SHA256).
REM ============================================================================
setlocal
pushd "%~dp0"
set "SRC=..\src"
set "OUT=."
set "DEFS="
if /i "%~1"=="selftest" (set "OUT=selftest" & set "DEFS=/DSHIM_SELFTEST")
if not exist "%OUT%" mkdir "%OUT%"

call ..\tools\dev\vsenv.bat || (popd & endlocal & exit /b 1)

set "CLFLAGS=/c /nologo /O2 /GS- /utf-8 /Brepro %DEFS%"
echo === Assembling thunks ===
ml.exe /nologo /c /coff /Cx /Fo"%OUT%\vbox52_thunks.obj" "%SRC%\vbox52_thunks.asm" || goto :fail
ml.exe /nologo /c /coff /Cx /Fo"%OUT%\imachine_entries.obj" "%SRC%\imachine_entries.asm" || goto :fail

echo === Compiling proxy ===
cl.exe %CLFLAGS% /Fo"%OUT%\vbox52_proxy.obj" "%SRC%\vbox52_proxy.cpp" || goto :fail
cl.exe %CLFLAGS% /Fo"%OUT%\spoof_thunks.obj" "%SRC%\spoof_thunks.cpp" || goto :fail

echo === Linking ===
link.exe /nologo /dll /Brepro /out:"%OUT%\VBox52.dll" /def:"%SRC%\vbox52.def" ^
  "%OUT%\vbox52_proxy.obj" "%OUT%\vbox52_thunks.obj" "%OUT%\spoof_thunks.obj" "%OUT%\imachine_entries.obj" ^
  ole32.lib oleaut32.lib psapi.lib advapi32.lib || goto :fail

echo === Done: %~dp0%OUT%\VBox52.dll ===
dumpbin /nologo /exports "%OUT%\VBox52.dll" | findstr /i "VBoxInstance SelfTest"
for /f "delims=" %%h in ('certutil -hashfile "%OUT%\VBox52.dll" SHA256 ^| findstr /v ":"') do echo SHA256: %%h
popd & endlocal & exit /b 0

:fail
echo BUILD FAILED
popd & endlocal & exit /b 1
