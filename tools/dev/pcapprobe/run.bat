@echo off
rem ============================================================================
rem  Call the system packet.dll from a 32-bit process exactly the way eNSP's
rem  Cloud plugin does (PacketGetVersion + PacketGetAdapterNames) and dump the
rem  raw result. Compare the output under WinPcap 4.1.3 and under Npcap in
rem  WinPcap-compatible mode; see docs\findings\cloud-npcap.md.
rem ============================================================================
setlocal
pushd "%~dp0"
if not exist out mkdir out
call ..\vsenv.bat || (popd & exit /b 1)
cl.exe /nologo /O2 /utf-8 /EHsc pkt.cpp /Fo"out\\" /Fe"out\pkt.exe" >nul || (echo [!] build failed & popd & exit /b 1)
out\pkt.exe
popd
