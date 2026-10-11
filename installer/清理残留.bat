@echo off
chcp 936 >nul
cd /d "%~dp0"
title ensp-vbox7-kit 清理残留进程

rem ---- 需要管理员权限：没有就申请提权，并以管理员身份重新运行本脚本 ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 清理残留进程需要管理员权限，请在弹出的 UAC 窗口中点“是”……
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo   ensp-vbox7-kit 清理残留进程
echo.
echo   项目地址  https://github.com/satsuki887/ensp-vbox7-kit
echo   基于      https://github.com/LBXaaa/ensp-vbox-shim
echo   本工具免费开源。若是付费获得，则为他人倒卖。
echo ------------------------------------------------------------
echo   用途：关闭设备或 eNSP 后，VBoxHeadless.exe 有时迟迟不退出
echo         （每个最多约占 1.5 GB 内存）。本脚本找出这些进程并结束它们。
echo   范围：eNSP 已关闭时，eNSP 设备的 VBoxHeadless 都算残留；
echo         eNSP 运行中时，只结束 VirtualBox 记录里已不在运行的孤儿进程，
echo         正在使用的设备不受影响。不属于 eNSP 的虚拟机一律不碰。
echo   结束前会先列出清单，经你确认后才执行。
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cleanup_orphans.ps1"

echo.
echo ------------------------------------------------------------
echo 清理流程结束，按任意键关闭窗口。
pause >nul
