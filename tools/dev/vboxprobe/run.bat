@echo off
rem ============================================================================
rem  Ground truth for the IVirtualBox vtable of the INSTALLED VirtualBox.
rem
rem  1. dump_tlb.ps1 (run in 32-bit PowerShell) reads the type library that a
rem     32-bit client such as eNSP actually uses (x86\VBoxProxyStub-x86.dll) and
rem     writes out\tlb.tsv: interface, vtable slot, method, parameter count.
rem  2. probe.exe (32-bit) talks to the real VBoxSVC: get_Version at [7], the
rem     reserved getter at [41] (expects E_NOTIMPL), FindMachine at [53].
rem     Read-only; needs a registered VM called AR_Base (eNSP's AR base disk).
rem
rem  Re-run this after every VirtualBox upgrade before trusting any slot table.
rem ============================================================================
setlocal
pushd "%~dp0"
if not exist out mkdir out
set "VBOX=%ProgramFiles%\Oracle\VirtualBox"
"%SystemRoot%\SysWOW64\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File dump_tlb.ps1 -TlbPath "%VBOX%\x86\VBoxProxyStub-x86.dll" > out\tlb.tsv
echo === type library: selected IVirtualBox slots ===
findstr /i /c:"get_Version" /c:"Attribute1IVirtualBox" /c:"Attribute12IVirtualBox" /c:"OpenMachine" /c:"RegisterMachine" /c:"FindMachine" /c:"GetExtraData" out\tlb.tsv | findstr /b IVirtualBox
echo (full table: %~dp0out\tlb.tsv)
call ..\vsenv.bat || (popd & exit /b 1)
cl.exe /nologo /O2 /utf-8 /EHsc probe.cpp ole32.lib oleaut32.lib /Fo"out\\" /Fe"out\probe.exe" >nul || (echo [!] build failed & popd & exit /b 1)
echo === runtime probe ===
out\probe.exe
popd
