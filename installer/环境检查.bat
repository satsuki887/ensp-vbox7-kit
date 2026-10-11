@echo off
chcp 936 >nul
cd /d "%~dp0"
title ensp-vbox7-kit 环境检查

rem ============================================================
rem  环境检查：采集 eNSP 与 VirtualBox 的环境信息，生成一份报告文件。
rem
rem  采集的是当前用户的 VirtualBox 配置，所以要用平时启动 eNSP 的账户
rem  直接双击本文件；换成其他管理员账户，读到的是那个账户的配置，
rem  结论和 eNSP 的实际情况对不上。
rem
rem  不带 -Fix 时全程只读，不修改任何系统设置。
rem ============================================================

echo ============================================================
echo   ensp-vbox7-kit 环境检查
echo.
echo   项目地址  https://github.com/satsuki887/ensp-vbox7-kit
echo   基于      https://github.com/LBXaaa/ensp-vbox-shim
echo   本工具免费开源。若是付费获得，则为他人倒卖。
echo ------------------------------------------------------------
echo   用途：采集 eNSP 与 VirtualBox 的环境信息并生成报告，报告可直接附在 issue 里。
echo         报告第 [9] 节列出查出的问题、影响和对应的修复命令。
echo   注意：请用平时启动 eNSP 的账户运行。不带 -Fix 时全程只读。
echo.
echo   用法（在命令提示符中运行时可带参数）：
echo     环境检查.bat                     只生成报告（只读）
echo     环境检查.bat -Fix                执行全部无损修复
echo     环境检查.bat -Fix all            连同需确认的修复一起执行，逐条确认
echo     环境检查.bat -Fix firewall       只执行指定项（id 见报告第 [9] 节）
echo     环境检查.bat -Fix all -DryRun    只列出计划，不执行
echo     环境检查.bat -Fix all -Yes       跳过逐条确认
echo   修复需要管理员权限：请在“以管理员身份运行”的命令提示符中执行 -Fix。
echo   报告保存在 %ProgramData%\ensp-vbox-shim\ 下。
echo ============================================================
echo.

rem 只写 -Fix 而不跟值时，补成 -Fix lossless（只做无损修复）。
rem diag.ps1 的 -Fix 是字符串参数，不带值会被 PowerShell 判为“缺少参数”
rem 而报错，所以在这一层补上默认值。
set "ARGS=%*"
if /i "%~1"=="-fix" if "%~2"=="" set "ARGS=-Fix lossless"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diag.ps1" %ARGS%

set "RC=%errorlevel%"
if not "%RC%"=="0" (
    echo.
    echo ------------------------------------------------------------
    echo 检查或修复没有全部成功，退出码 %RC%。
    echo 如需求助，请把生成的报告文件附在 issue 里提交：
    echo https://github.com/satsuki887/ensp-vbox7-kit/issues
)

echo.
echo ------------------------------------------------------------
echo 环境检查结束，按任意键关闭窗口。
pause >nul
