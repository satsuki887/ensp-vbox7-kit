<#
.SYNOPSIS
    Generate installer\payload\VAR_Plugin.dll from YOUR OWN eNSP installation.

.DESCRIPTION
    VAR_Plugin.dll is Huawei's file, so this repository does not ship it. The
    installer still needs the patched copy in installer\payload\, so this
    script builds it locally:

      1. Find eNSP (uninstall registry entry, then the default paths).
      2. Take the factory plugin: plugin\ar1000v\VAR_Plugin.dll.orig.bak if a
         previous install left one, otherwise plugin\ar1000v\VAR_Plugin.dll.
      3. If it is the 2019 factory build, run patches\patch_var_plugin.py on a
         copy; if it is already the patched build, copy it as is. Anything
         else is refused (the patcher only knows that one build).

    Read-only towards eNSP: it never writes under Program Files, so it needs
    no administrator rights. Requires Python 3 on PATH (py or python).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools\prepare-payload.ps1
    powershell -ExecutionPolicy Bypass -File tools\prepare-payload.ps1 -EnspDir "D:\eNSP"
#>
[CmdletBinding()]
param([string]$EnspDir = "")

$ErrorActionPreference = "Stop"
$repo    = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Definition)
$payload = Join-Path $repo "installer\payload\VAR_Plugin.dll"
$patcher = Join-Path $repo "patches\patch_var_plugin.py"

# Same constants as patches\patch_var_plugin.py / installer\install.ps1.
$PRISTINE = "5ae6817a9f2f05cfbb5f1f89af910007c22988c22bc02fdf2c44a67a9ff26eb5"
$PATCHED  = "f0107975ba1b04325af2d31189ee92833233c1163f4553600207789977f94451"

function Find-Ensp {
    if ($EnspDir) { if (Test-Path (Join-Path $EnspDir "plugin")) { return $EnspDir.TrimEnd('\') }; return $null }
    foreach ($root in "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                      "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall") {
        foreach ($k in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -like "*eNSP*" -and $p.InstallLocation -and (Test-Path (Join-Path $p.InstallLocation "plugin"))) {
                return $p.InstallLocation.TrimEnd('\')
            }
        }
    }
    foreach ($d in "${env:ProgramFiles(x86)}\Huawei\eNSP", "$env:ProgramFiles\Huawei\eNSP") {
        if (Test-Path (Join-Path $d "plugin")) { return $d }
    }
    return $null
}
function Get-Sha([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }

function Say-OK([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Say-Info([string]$m) { Write-Host "  [..] $m" -ForegroundColor Gray }
function Say-Err([string]$m)  { Write-Host "  [XX] $m" -ForegroundColor Red }

if ((Test-Path $payload) -and ((Get-Sha $payload) -eq $PATCHED)) {
    Say-OK "installer\payload\VAR_Plugin.dll 已是补丁版,无需重新生成。"
    exit 0
}

$ensp = Find-Ensp
if (-not $ensp) {
    Say-Err "找不到 eNSP 安装目录。请用 -EnspDir 指定,例如 -EnspDir `"D:\Huawei\eNSP`"。"
    exit 1
}
$dir = Join-Path $ensp "plugin\ar1000v"
$src = $null
foreach ($cand in (Join-Path $dir "VAR_Plugin.dll.orig.bak"), (Join-Path $dir "VAR_Plugin.dll")) {
    if (Test-Path $cand) { $h = Get-Sha $cand; if ($h -eq $PRISTINE -or $h -eq $PATCHED) { $src = $cand; break } }
}
if (-not $src) {
    Say-Err "在 $dir 下没有找到可识别的 VAR_Plugin.dll。"
    Say-Info "补丁器只支持 eNSP 1.3.00.100 自带的版本(SHA256 $($PRISTINE.Substring(0,12))…)。"
    Say-Info "如果 eNSP 版本不同或插件被改过,请先重装 eNSP 1.3.00.100。"
    exit 1
}
Say-Info "eNSP 目录 : $ensp"
Say-Info "来源文件  : $src"

New-Item -ItemType Directory -Force (Split-Path $payload) | Out-Null
Copy-Item $src $payload -Force
if ((Get-Sha $payload) -eq $PRISTINE) {
    $py = (Get-Command py, python -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $py) {
        Remove-Item $payload
        Say-Err "找不到 Python 3(PATH 里需要有 py 或 python)。"
        Say-Info "从 https://www.python.org/downloads/windows/ 安装,勾选 Add python.exe to PATH 后重试。"
        exit 1
    }
    Say-Info "正在用 patches\patch_var_plugin.py 打补丁…"
    $pyArgs = @("-I", $patcher, "--no-backup", $payload)
    if ((Split-Path $py -Leaf) -ieq "py.exe") { $pyArgs = @("-3") + $pyArgs }
    & $py @pyArgs
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $payload -ErrorAction SilentlyContinue
        Say-Err "补丁器运行失败(原因见上方输出),已删除半成品。"
        exit 1
    }
}
if ((Get-Sha $payload) -ne $PATCHED) {
    Remove-Item $payload -ErrorAction SilentlyContinue
    Say-Err "生成结果与预期的补丁版不一致,已删除。"
    exit 1
}
Say-OK "已生成 installer\payload\VAR_Plugin.dll(SHA256 $($PATCHED.Substring(0,12))…)。"
