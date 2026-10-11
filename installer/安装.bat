@echo off
chcp 936 >nul
cd /d "%~dp0"
title ensp-vbox7-kit 安装

echo ============================================================
echo   ensp-vbox7-kit 安装 —— 让原版华为 eNSP 运行在 VirtualBox 7.2 上
echo.
echo   项目地址  https://github.com/satsuki887/ensp-vbox7-kit
echo   基于      https://github.com/LBXaaa/ensp-vbox-shim
echo   本工具免费开源。若是付费获得，则为他人倒卖。
echo ============================================================
echo.
echo   开始前请关闭 eNSP 和 VirtualBox。
echo   流程：安装前检查 → 部署垫片（弹一次 UAC）→ 注册基础设备 → 环境检测
echo.

rem This launcher does NOT self-elevate; it stays in the double-clicking
rem user's context (the user who normally launches eNSP). Elevation happens
rem only inside install_all.ps1 when it relaunches install.ps1 as an elevated
rem child. The VM-registration step then runs under THIS non-elevated user
rem token, so the VMs register into the correct %USERPROFILE%.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_all.ps1" %*

echo.
echo ------------------------------------------------------------
echo 安装流程结束，按任意键关闭窗口。
pause >nul
