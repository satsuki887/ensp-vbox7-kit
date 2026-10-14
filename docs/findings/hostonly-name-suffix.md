# host-only 网卡名带「#N」后缀，eNSP 认不出

**状态：已修复（诊断修复项 `hostonly-name`）**；占名记录那一种情形仍需手动处理 · 记录于 2026-10-14

本文是 [`troubleshooting-error40.md`](../troubleshooting-error40.md) 根因 G 的详细记录：两次实测、名字写死在哪里、
后缀从哪来、注册表残留的完整处理步骤，以及试过但无效的做法。只想修好设备的话，看根因 G 即可。

## 现象（修复前）

- AR（以及 AC / AP、防火墙等真 VM 设备）一启动就报错误 40，交换机正常。
- 垫片日志全绿：`findMachine` / `clonevm` / `modifyvm` 都成功，失败在随后的 `startvm`。
- `eNSP\vboxserver\log\VBoxManage.log`：

  ```
  VBoxManage.exe: error: Interface ('VirtualBox Host-Only Ethernet Adapter') is not a Host-Only Adapter interface (VERR_INTERNAL_ERROR)
  ```

- `VBoxManage list hostonlyifs` 只有 `VirtualBox Host-Only Ethernet Adapter #2`、`#3` 这类带后缀的网卡。

## 名字写死在哪里

逐字是 `VirtualBox Host-Only Ethernet Adapter`，在 eNSP 1.3.00.100 的这些文件里都能找到（2026-10-14 检索）：

| 位置 | 用法 |
|---|---|
| `vboxserver\*_Base\*_Base.vbox` | `HostOnlyInterface name=`，实况段和 `_Link` 快照段各一份；克隆从快照出，用的是后一份 |
| `plugin\ar1000v\VAR_Plugin.dll`、`plugin\ngfw\NGFW_Plugin.dll`、`eNSP_Client.exe` | 字符串常量 |
| `vboxserver\eNSP_VBoxServer.exe` | 启动时执行 `hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 ...` |

所以要改的是网卡，不是 eNSP。曾有一种说法是"重新注册设备会重写模板里的名字"，不成立：`register_vms.ps1` 从不改网卡名，
插件里的那几份也不在模板里。改二进制也行不通：该字符串后面只剩 3 个空闲字节，放不下 `" #2"`。

## 后缀从哪来

VirtualBox 显示的网卡名就是 Windows 网络组件的描述名，后缀由 Windows 在**建网卡时**分配：只有在没有别的接口记录
占着这个描述名时，新网卡才拿到不带后缀的名字。占名的可能是：

1. **还在的另一块 host-only 网卡**（包括带后缀的旧网卡）。这时新建只会拿到下一个编号，必须先删再建。
2. **已删除网卡留下的接口记录**：`HKLM\SYSTEM\CurrentControlSet\Control\NetworkSetup2\Interfaces\{GUID}\Kernel`
   下 `IfDescr` 为不带后缀的名字。删网卡、重装驱动、重启都清不掉它。

改 `Enum\ROOT\NET\<n>\FriendlyName`、Class 键的 `DriverDesc`、`Connection\Name` 都不影响 VirtualBox 看到的名字
（`Get-NetAdapter` 立刻变，`VBoxManage list hostonlyifs` 不变）。

## 两次实测

**2026-10-14，VirtualBox 7.2.16，Windows 11 家庭版 build 26300，i5-11300H。** 新装 VirtualBox、WinPcap、eNSP 后直接运行
`安装.bat`，安装提示成功，AR 报 40。唯一的网卡叫 `#3`，`Get-PnpDevice` 里没有隐藏的残留网卡设备；
`Control\Network\{4D36E972-...}\Descriptions` 下该描述名只记着 `3`。属于情形 1：

1. `hostonlyif remove "... #3"`，然后 `hostonlyif create`，拿到不带后缀的名字；`ipconfig` 配 `192.168.56.1`。
2. AR 的报错随即变成 `VERR_INTNET_FLT_IF_NOT_FOUND`：过滤驱动绑定显示已启用，却没进数据路径（同 D1）。
3. 禁用 / 启用该网卡并结束 `VBoxSVC.exe` 后，AR、Cloud、接口抓包全部正常。

当时安装前检查已打出"模板名匹配 0 / 2"，但诊断没有对应修复项，提示里还写着"重新注册设备"，安装器于是照常显示成功。
此后新增了修复项 `hostonly-name`，安装结束时的运行时检测会直接提出它。

**2026-09-06，VirtualBox 5.2.44，Windows 11 家庭版，eNSP V100R003C00SPC100。** 同样的报错，属于情形 2：
`NetworkSetup2\Interfaces` 里有一条 `IfDescr` 不带后缀的已删除网卡记录，删网卡重建、只重启、多建一块都无效
（多建只会得到更大的编号）。按下一节删掉记录并重启后，新建的网卡名字干净，设备恢复。

## 情形 2 的处理：删除占名记录

> 这些步骤来自 2026-09-06 的 5.2 环境。它们只涉及 Windows 网络组件，与 VirtualBox 版本无关，但在 7.2 上还没有遇到需要
> 走到这一步的机器。`hostonly-name` 修复遇到这种情况会停下并说明，不会继续多建网卡。

**1. 取得 `NetworkSetup2` 的读写权限。** 该键归 TrustedInstaller 所有，管理员和 SYSTEM 默认都读不了
（`reg query` 报"拒绝访问"，非提权的 PowerShell 读到 0 条）。可以用以 TrustedInstaller 身份运行的 `regedit` 手工操作，
也可以用下面的脚本，经 SYSTEM 计划任务把所有者改为 Administrators 并授予完全控制。

`C:\temp\take-own.ps1`（只用英文：Windows PowerShell 5.1 按 ANSI 读取无 BOM 的脚本，中文会破坏解析）：

```powershell
$code = @"
using System;
using System.Runtime.InteropServices;
public class Priv {
  [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] public struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }
  [StructLayout(LayoutKind.Sequential)] public struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr h, uint acc, out IntPtr tok);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool LookupPrivilegeValue(string sys, string name, out LUID luid);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool AdjustTokenPrivileges(IntPtr tok, bool dis, ref TOKEN_PRIVILEGES newst, uint len, IntPtr prev, IntPtr ret);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
  public static bool Enable(string name) {
    IntPtr tok;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out tok)) return false;
    LUID luid;
    if (!LookupPrivilegeValue(null, name, out luid)) return false;
    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
    tp.PrivilegeCount = 1; tp.Privileges.Luid = luid; tp.Privileges.Attributes = 0x00000002;
    return AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
[Priv]::Enable('SeTakeOwnershipPrivilege') | Out-Null
[Priv]::Enable('SeRestorePrivilege') | Out-Null

$path = 'SYSTEM\CurrentControlSet\Control\NetworkSetup2'
$admins = New-Object System.Security.Principal.NTAccount("BUILTIN","Administrators")

$key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
$acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
$acl.SetOwner($admins)
$key.SetAccessControl($acl)
$key.Close()

$key2 = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
$acl2 = $key2.GetAccessControl()
$rule = New-Object System.Security.AccessControl.RegistryAccessRule($admins,"FullControl","ContainerInherit","None","Allow")
$acl2.SetAccessRule($rule)
$key2.SetAccessControl($acl2)
$key2.Close()
"OWNERSHIP TAKEN OK"
```

`C:\temp\take-own.bat`：

```bat
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0take-own.ps1" > "%~dp0take-own-result.txt" 2>&1
```

管理员 PowerShell 中执行，看到 `OWNERSHIP TAKEN OK` 即成功：

```powershell
schtasks /create /tn "TakeOwnNS2" /tr "C:\temp\take-own.bat" /sc once /st 00:00 /ru SYSTEM /rl HIGHEST /f
schtasks /run /tn "TakeOwnNS2"
Start-Sleep -Seconds 15
schtasks /delete /tn "TakeOwnNS2" /f
Get-Content "C:\temp\take-own-result.txt"
```

**2. 备份，删网卡，删记录。** 管理员 PowerShell（关闭 eNSP）：

```powershell
reg export "HKLM\SYSTEM\CurrentControlSet\Control\NetworkSetup2\Interfaces" "C:\temp\ns2_backup.reg" /y
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}" "C:\temp\network_backup.reg" /y

$VB = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VB list hostonlyifs | Select-String "^Name:" | ForEach-Object {
  & $VB hostonlyif remove (($_.Line -replace "^Name:\s*", "").Trim())
}
Start-Sleep -Seconds 6

$root = 'HKLM:\SYSTEM\CurrentControlSet\Control\NetworkSetup2\Interfaces'
Get-ChildItem $root | ForEach-Object {
  $kk = Join-Path $_.PSPath 'Kernel'
  $d = ''
  if (Test-Path $kk) { $d = (Get-ItemProperty $kk -ErrorAction SilentlyContinue).IfDescr }
  if ($d -match 'VirtualBox Host-Only') {
    "deleting {0} ({1})" -f $_.PSChildName, $d
    Remove-Item -LiteralPath $_.PSPath -Recurse -Force
  }
}

$dk = 'HKLM:\SYSTEM\CurrentControlSet\Control\Network\{4D36E972-E325-11CE-BFC1-08002BE10318}\Descriptions'
Remove-ItemProperty -Path $dk -Name "VirtualBox Host-Only Ethernet Adapter" -Force -ErrorAction SilentlyContinue
```

**3. 重启，然后才建网卡。** 删完记录不重启就 `hostonlyif create`，VirtualBox 报 `Assertion failed: [!aInterfaceName.isEmpty()]`：
网卡其实建出来了、名字也干净，但设备停在 `CM_PROB_FAILED_ADD`，禁用 / 启用、`pnputil /scan-devices` 都救不回来，只能重启；
这时再 `create` 又会多一块 `#2`。

**4. 重启后建网卡并配置**，与情形 1 相同：

```powershell
$VB = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $VB hostonlyif create
& $VB hostonlyif ipconfig "VirtualBox Host-Only Ethernet Adapter" --ip 192.168.56.1 --netmask 255.255.255.0
Disable-NetAdapter -InterfaceDescription "VirtualBox Host-Only Ethernet Adapter" -Confirm:$false
Start-Sleep 5
Enable-NetAdapter  -InterfaceDescription "VirtualBox Host-Only Ethernet Adapter" -Confirm:$false
```

**回滚**：导入备份的 `ns2_backup.reg` / `network_backup.reg`。改过的所有者不会自动恢复；需要的话在 `regedit` 的
"权限 → 高级"里把 `NetworkSetup2` 的所有者改回 `NT SERVICE\TrustedInstaller`（原记录没有做这一步）。

## 无效的做法

| 做法 | 结果 |
|---|---|
| 改 `Enum\ROOT\NET\<n>\FriendlyName`、Class 键的 `DriverDesc` | `Get-NetAdapter` 显示的名字变了，`VBoxManage list hostonlyifs` 不变 |
| 改 `Connection\Name`、`DefaultNameIndex` | 无效，网络配置组件有内存态缓存 |
| 只把 `Descriptions` 索引改成 `1` | 重建时被写回 |
| 有占名记录时删网卡重建、卸载重装 `VBoxNetAdp6` 驱动包、只重启不删记录 | 照样带后缀 |
| 再多建一块，指望补上空出来的编号 | 只会得到更大的编号 |
| 让网卡占到 `ROOT\NET\0000` | 无关，后缀与设备序号无关 |
| 改 eNSP 二进制里的字符串 | 放不下（见上文） |
| 把模板的 `HostOnlyInterface name=` 改成带后缀的名字 | 未验证；插件与 `eNSP_VBoxServer.exe` 里的仍是出厂名，不建议 |

## 与 Hyper-V 的关系（仅 VirtualBox 5.2）

2026-09-06 那台 5.2 机器上，修好网卡名之前还先遇到了 `Raw-mode is unavailable courtesy of Hyper-V
(VERR_SUPDRV_NO_RAW_MODE_HYPER_V_ROOT)`，当时靠 `bcdedit /set hypervisorlaunchtype off` 并重启解决。**这只适用于 5.2**：
5.2 与 Hyper-V 互斥。本项目面向 VirtualBox 7.x，它通过 WHP 与 Hyper-V 共存，开着 Hyper-V 只是设备启动变慢，
不会报 40，**不要**为本项目关闭 Hyper-V / VBS（理由见 `环境检查.bat` 报告第 [2] 节）。
