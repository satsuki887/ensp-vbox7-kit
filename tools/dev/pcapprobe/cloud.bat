@echo off
rem ============================================================================
rem  Run eNSP_Cloud_Plugin.dll's adapter enumeration outside eNSP, once with the
rem  system packet.dll (WinPcap) and once with Npcap's, and print what the Cloud
rem  dialog would list. Uses a copy of the plugin from your eNSP install; nothing
rem  under Program Files is changed. See docs\findings\cloud-npcap.md.
rem
rem    cloud.bat ["C:\Program Files\Huawei\eNSP"]
rem ============================================================================
setlocal
set "ENSP=%~1"
if not defined ENSP set "ENSP=C:\Program Files\Huawei\eNSP"
pushd "%~dp0"
call ..\vsenv.bat || (popd & exit /b 1)
for %%d in (out\sys out\npcap) do if not exist %%d mkdir %%d
cl.exe /nologo /O2 /EHsc cloudenum.cpp /Fo"out\\" /Fe"out\sys\cloudenum.exe" >nul || (echo [!] build failed & popd & exit /b 1)
copy /y out\sys\cloudenum.exe out\npcap\ >nul
copy /y "%ENSP%\tools\eNSP_Cloud_Plugin.dll" out\sys\ >nul || (echo [!] plugin not found under %ENSP% & popd & exit /b 1)
copy /y "%ENSP%\tools\eNSP_Cloud_Plugin.dll" out\npcap\ >nul
if exist "%SystemRoot%\SysWOW64\Npcap\Packet.dll" (copy /y "%SystemRoot%\SysWOW64\Npcap\Packet.dll" out\npcap\ >nul) else (echo [..] Npcap not installed)
rem The exe's own directory decides which packet.dll it binds to.
echo ===== system packet.dll
"%~dp0out\sys\cloudenum.exe"
if exist out\npcap\Packet.dll (echo ===== Npcap packet.dll & "%~dp0out\npcap\cloudenum.exe")
popd
