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

if ((Test-Path $payload) -and ((Get-Sha $payload) -eq $PATCHED)) {
    Write-Host "[OK] installer\payload\VAR_Plugin.dll is already the patched build. Nothing to do." -ForegroundColor Green
    exit 0
}

$ensp = Find-Ensp
if (-not $ensp) { Write-Host "[XX] eNSP not found. Pass -EnspDir." -ForegroundColor Red; exit 1 }
$dir = Join-Path $ensp "plugin\ar1000v"
$src = $null
foreach ($cand in (Join-Path $dir "VAR_Plugin.dll.orig.bak"), (Join-Path $dir "VAR_Plugin.dll")) {
    if (Test-Path $cand) { $h = Get-Sha $cand; if ($h -eq $PRISTINE -or $h -eq $PATCHED) { $src = $cand; break } }
}
if (-not $src) {
    Write-Host "[XX] No known VAR_Plugin.dll under $dir." -ForegroundColor Red
    Write-Host "     The patcher only supports the 2019 factory build (sha256 $($PRISTINE.Substring(0,12))...)."
    exit 1
}
Write-Host "eNSP   : $ensp"
Write-Host "source : $src"

New-Item -ItemType Directory -Force (Split-Path $payload) | Out-Null
Copy-Item $src $payload -Force
if ((Get-Sha $payload) -eq $PRISTINE) {
    $py = (Get-Command py, python -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $py) { Remove-Item $payload; Write-Host "[XX] Python 3 not found (need py or python on PATH)." -ForegroundColor Red; exit 1 }
    $pyArgs = @("-I", $patcher, "--no-backup", $payload)
    if ((Split-Path $py -Leaf) -ieq "py.exe") { $pyArgs = @("-3") + $pyArgs }
    & $py @pyArgs
    if ($LASTEXITCODE -ne 0) { Remove-Item $payload -ErrorAction SilentlyContinue; Write-Host "[XX] patcher failed." -ForegroundColor Red; exit 1 }
}
if ((Get-Sha $payload) -ne $PATCHED) {
    Remove-Item $payload -ErrorAction SilentlyContinue
    Write-Host "[XX] Result does not match the expected patched build; removed it." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Wrote installer\payload\VAR_Plugin.dll (sha256 $($PATCHED.Substring(0,12))...)." -ForegroundColor Green
