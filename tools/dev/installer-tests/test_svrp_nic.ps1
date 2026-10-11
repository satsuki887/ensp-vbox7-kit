<#
.SYNOPSIS
    Sandbox test for Set-UnattachedVirtioNics (the SVRP shutdown-crash fix).

.DESCRIPTION
    Pulls Set-UnattachedVirtioNics / Get-VmInfoMap out of installer\install.ps1
    via the AST (nothing at the top level of install.ps1 runs), registers a
    throw-away diskless VM under a temp directory that stands in for the eNSP
    directory, and checks both directions:

      install    nic1 null+virtio  -> intnet ensp-unused-<vm>-nic1
                 nic2 nat+virtio   -> unchanged
                 nic3 null+82540EM -> unchanged (only virtio is affected)
      uninstall  nic1              -> null again; nic2 / nic3 unchanged

    VMs whose settings file is outside the temp directory -- the real eNSP
    ones included -- are filtered out by the function itself and never
    modified. The test VM is unregistered and deleted at the end.
    Needs VirtualBox; no elevation. Exit code 0 = all cases as expected.
#>
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$inst = Join-Path $repo "installer\install.ps1"
$ast  = [System.Management.Automation.Language.Parser]::ParseFile($inst, [ref]$null, [ref]$null)
foreach ($name in 'Set-UnattachedVirtioNics','Get-VmInfoMap','Write-OK','Write-Info','Write-Err','Write-Warn') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
}
$as = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$UNUSED_INTNET_PREFIX' }, $true)
. ([scriptblock]::Create($as.Extent.Text))

$vboxDir = (Get-ItemProperty "HKLM:\SOFTWARE\Oracle\VirtualBox" -ErrorAction SilentlyContinue).InstallDir
if (-not $vboxDir) { $vboxDir = "C:\Program Files\Oracle\VirtualBox\" }
$vbm = Join-Path $vboxDir "VBoxManage.exe"

$sb = Join-Path $env:TEMP ("svrpnictest-" + [guid]::NewGuid())
New-Item -ItemType Directory $sb | Out-Null
$vm = "svrpnictest-" + [guid]::NewGuid().ToString().Substring(0, 8)
& $vbm createvm --name $vm --basefolder $sb --register 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { "[FAIL] createvm rc=$LASTEXITCODE"; exit 1 }
& $vbm modifyvm $vm --nic1 null --nictype1 virtio --nic2 nat --nictype2 virtio --nic3 null --nictype3 82540EM 2>$null | Out-Null

$fail = 0
function Expect($label, $key, $want) {
    $got = (Get-VmInfoMap $vbm $vm)[$key]
    $ok = $got -eq $want
    '{0} {1,-22} {2,-10} = {3}' -f $(if ($ok) { "[ok]  " } else { "[FAIL]" }), $label, $key, $got
    if (-not $ok) { $script:fail++ }
}
try {
    Set-UnattachedVirtioNics -VBoxDir $vboxDir -EnspDir $sb | Out-Null
    Expect 'install'   'nic1'    'intnet'
    Expect 'install'   'intnet1' "$UNUSED_INTNET_PREFIX$vm-nic1"
    Expect 'install'   'nic2'    'nat'
    Expect 'install'   'nic3'    'null'
    Set-UnattachedVirtioNics -VBoxDir $vboxDir -EnspDir $sb | Out-Null
    Expect 'install again' 'nic1' 'intnet'
    Set-UnattachedVirtioNics -VBoxDir $vboxDir -EnspDir $sb -Revert | Out-Null
    Expect 'uninstall' 'nic1'    'null'
    Expect 'uninstall' 'nictype1' 'virtio'
    Expect 'uninstall' 'nic2'    'nat'
    Expect 'uninstall' 'nic3'    'null'
    # VBoxManage errors (stderr) must not become terminating errors under Stop.
    try { $none = Get-VmInfoMap $vbm "no-such-vm-$([guid]::NewGuid())"; $ok = $none.Count -eq 0 } catch { $ok = $false }
    '{0} {1,-22} {2}' -f $(if ($ok) { "[ok]  " } else { "[FAIL]" }), 'unknown vm', 'no exception, empty map'
    if (-not $ok) { $fail++ }
} finally {
    $ErrorActionPreference = "Continue"   # VBoxManage prints its progress bar on stderr
    & $vbm unregistervm $vm --delete 2>$null | Out-Null
    Remove-Item $sb -Recurse -Force -ErrorAction SilentlyContinue
}
if ($fail) { "$fail check(s) FAILED"; exit 1 }
"ALL PASSED"
