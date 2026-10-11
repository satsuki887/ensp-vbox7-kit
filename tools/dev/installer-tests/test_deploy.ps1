<#
.SYNOPSIS
    Sandbox test for the installer's upgrade/uninstall file handling.

.DESCRIPTION
    Pulls Deploy-PayloadFile / Remove-DeployedFile / Restore-FromBak and the
    hash constants straight out of installer\install.ps1 (via the AST, so
    nothing at the top level of install.ps1 runs) and exercises them in a temp
    directory. Never touches eNSP or Program Files.

      A  location held a non-shim file    -> backed up, restored on uninstall
      B  location held an older shim      -> overwritten WITHOUT backup, removed
      C  uninstall meets an older shim    -> removed

    The "older shim" is upstream's prebuilt VBox52.dll taken from git history
    (it is listed in PREV_DLL_SHA256). Exit code 0 = all cases as expected.
#>
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$inst = Join-Path $repo "installer\install.ps1"
$ast  = [System.Management.Automation.Language.Parser]::ParseFile($inst, [ref]$null, [ref]$null)
foreach ($name in 'Deploy-PayloadFile','Remove-DeployedFile','Restore-FromBak','Write-OK','Write-Info','Write-Err','Write-Warn') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
foreach ($var in 'DLL_SHA256','PREV_DLL_SHA256') {
    $as = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq "`$$var" }, $true)
    . ([scriptblock]::Create($as.Extent.Text))
}
$ScriptDir = Join-Path $repo "installer"     # Deploy-PayloadFile reads payload\ relative to this

$sb = Join-Path $env:TEMP ("deploytest-" + [guid]::NewGuid())
New-Item -ItemType Directory $sb | Out-Null
$oldShim = Join-Path $sb "upstream-VBox52.dll"
# PowerShell's pipeline would mangle the binary blob; let cmd do the redirection.
cmd /c "git -C `"$repo`" cat-file blob d5cf369:installer/payload/VBox52.dll > `"$oldShim`""
$foreign = Join-Path $sb "foreign.dll"
[System.IO.File]::WriteAllBytes($foreign, [byte[]](1..64))   # stands in for a Huawei original

function Get-ShortHash($p) { if (Test-Path $p) { (Get-FileHash $p).Hash.ToLower().Substring(0,8) } else { "-" } }
$fail = 0
function Expect($label, $p, [bool]$fileWanted, [bool]$bakWanted, $fileHash = $null) {
    $f = Test-Path $p; $b = Test-Path "$p.orig.bak"
    $ok = ($f -eq $fileWanted) -and ($b -eq $bakWanted) -and (-not $fileHash -or ((Get-ShortHash $p) -eq $fileHash))
    '{0} {1,-34} file={2} bak={3}' -f $(if ($ok) { "[ok]  " } else { "[FAIL]" }), $label, (Get-ShortHash $p), (Get-ShortHash "$p.orig.bak")
    if (-not $ok) { $script:fail++ }
}
"upstream shim $(Get-ShortHash $oldShim) listed in PREV_DLL_SHA256: $($PREV_DLL_SHA256 -contains (Get-FileHash $oldShim).Hash.ToLower())"
$new = $DLL_SHA256.Substring(0,8)

$a = Join-Path $sb 'A\VBox52.dll'; New-Item -ItemType Directory (Split-Path $a) | Out-Null; Copy-Item $foreign $a
Deploy-PayloadFile 'VBox52.dll' $a $DLL_SHA256 | Out-Null
Expect 'A after deploy'     $a $true $true $new
$b = Join-Path $sb 'B\VBox52.dll'; New-Item -ItemType Directory (Split-Path $b) | Out-Null; Copy-Item $oldShim $b
Deploy-PayloadFile 'VBox52.dll' $b $DLL_SHA256 | Out-Null
Expect 'B after deploy'     $b $true $false $new
foreach ($p in $a, $b) { Restore-FromBak $p | Out-Null; Remove-DeployedFile $p (@($DLL_SHA256) + $PREV_DLL_SHA256) | Out-Null }
Expect 'A after uninstall'  $a $true $true (Get-ShortHash $foreign)
Expect 'B after uninstall'  $b $false $false
$c = Join-Path $sb 'C\VBox52.dll'; New-Item -ItemType Directory (Split-Path $c) | Out-Null; Copy-Item $oldShim $c
Remove-DeployedFile $c (@($DLL_SHA256) + $PREV_DLL_SHA256) | Out-Null
Expect 'C old shim, uninstall' $c $false $false

Remove-Item $sb -Recurse -Force
if ($fail) { "SOME FAILED ($fail)"; exit 1 } else { "ALL PASSED"; exit 0 }
