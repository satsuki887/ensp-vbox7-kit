@echo off
rem ============================================================================
rem  vsenv.bat -- set up a 32-bit MSVC build environment for this repo.
rem
rem  Usage:  call tools\dev\vsenv.bat      (from any build script)
rem
rem  1. Visual Studio: %VCVARS% if you set it, otherwise the newest install that
rem     has the x86/x64 C++ tools, found with vswhere (Community, Build Tools...).
rem  2. Windows SDK: the installed one if vcvars found it; otherwise the NuGet
rem     packages in local\toolchain\ (Microsoft.Windows.SDK.CPP + .x86, see
rem     docs\dependencies.md), extracted once into local\toolchain\sdk\.
rem ============================================================================
set "_REPO=%~dp0..\.."
if defined VCVARS goto :vcvars
set "_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%_VSWHERE%" (echo [!] vswhere.exe not found - install Visual Studio or set VCVARS & exit /b 1)
for /f "usebackq delims=" %%i in (`"%_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "_VSDIR=%%i"
if not defined _VSDIR (echo [!] no Visual Studio with C++ x86/x64 tools found - set VCVARS & exit /b 1)
set "VCVARS=%_VSDIR%\VC\Auxiliary\Build\vcvars32.bat"
:vcvars
if not exist "%VCVARS%" (echo [!] vcvars32.bat not found: "%VCVARS%" & exit /b 1)
call "%VCVARS%" >nul 2>&1
where cl.exe >nul 2>&1 || (echo [!] vcvars32 did not put cl.exe on PATH & exit /b 1)

rem ---- Windows SDK ------------------------------------------------------------
if defined WindowsSdkDir if exist "%WindowsSdkDir%Include\%WindowsSDKVersion%um\windows.h" goto :done
set "_TC=%_REPO%\local\toolchain"
set "_SDK=%_TC%\sdk"
set "_TAR=%SystemRoot%\System32\tar.exe"
if not exist "%_SDK%\cpp\c\Include" (
  if not exist "%_TC%\microsoft.windows.sdk.cpp.nupkg" (echo [!] no Windows SDK installed and local\toolchain\*.nupkg missing - see docs\dependencies.md & exit /b 1)
  echo [..] extracting Windows SDK NuGet packages into local\toolchain\sdk ...
  mkdir "%_SDK%\cpp" "%_SDK%\x86" 2>nul
  "%_TAR%" -xf "%_TC%\microsoft.windows.sdk.cpp.nupkg" -C "%_SDK%\cpp" || exit /b 1
  "%_TAR%" -xf "%_TC%\microsoft.windows.sdk.cpp.x86.nupkg" -C "%_SDK%\x86" || exit /b 1
)
for /d %%v in ("%_SDK%\cpp\c\Include\10.*") do set "_SDKI=%%v"
if not defined _SDKI (echo [!] unexpected SDK package layout under %_SDK% & exit /b 1)
set "INCLUDE=%INCLUDE%;%_SDKI%\um;%_SDKI%\shared;%_SDKI%\ucrt;%_SDKI%\winrt"
set "LIB=%LIB%;%_SDK%\x86\c\um\x86;%_SDK%\x86\c\ucrt\x86"
:done
exit /b 0
