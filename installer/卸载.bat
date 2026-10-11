@echo off
chcp 936 >nul
cd /d "%~dp0"
title ensp-vbox7-kit 卸载

rem ---- 需要管理员权限：没有就申请提权，并以管理员身份重新运行本脚本 ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 卸载需要管理员权限，请在弹出的 UAC 窗口中点“是”……
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================================
echo   ensp-vbox7-kit 卸载
echo.
echo   项目地址  https://github.com/satsuki887/ensp-vbox7-kit
echo   基于      https://github.com/LBXaaa/ensp-vbox-shim
echo   本工具免费开源。若是付费获得，则为他人倒卖。
echo ------------------------------------------------------------
echo   会还原：VirtualBox 版本号、AR 插件 VAR_Plugin.dll、x86 VC++ 运行时，
echo           并移除 eNSP 目录各处的 VBox52.dll 垫片。
echo   不会还原：CLSID 注册表项。卸载结束后请按屏幕上的提示手动删除。
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall

echo.
echo ------------------------------------------------------------
echo 卸载流程结束，按任意键关闭窗口。
pause >nul
