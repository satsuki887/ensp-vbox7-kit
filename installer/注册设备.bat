@echo off
chcp 936 >nul
cd /d "%~dp0"
title ensp-vbox7-kit 注册设备

rem ============================================================
rem  把 eNSP 的基础设备 VM 注册进 VirtualBox 7.x
rem
rem  本脚本不提权：VM 注册写入当前用户的 .VirtualBox\VirtualBox.xml，
rem  必须和平时启动 eNSP 的账户一致。以其他管理员账户运行会把注册写进
rem  那个账户的配置，eNSP 反而看不到。请用平时启动 eNSP 的账户直接双击。
rem ============================================================

echo ============================================================
echo   ensp-vbox7-kit 注册设备
echo.
echo   项目地址  https://github.com/satsuki887/ensp-vbox7-kit
echo   基于      https://github.com/LBXaaa/ensp-vbox-shim
echo   本工具免费开源。若是付费获得，则为他人倒卖。
echo ------------------------------------------------------------
echo   用途：把 eNSP 的基础设备 VM（AR_Base、WLAN_*_Base 等）注册进 VirtualBox。
echo         安装.bat 通常已自动完成这一步；只有安装时提示“已跳过自动注册”才需要运行本脚本。
echo   注意：请用平时启动 eNSP 的账户直接双击，不要“以管理员身份运行”。
echo   已正确注册的设备保持不动，可以放心重复运行。
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0register_vms.ps1"

echo.
echo ------------------------------------------------------------
echo 注册流程结束，按任意键关闭窗口。
pause >nul
