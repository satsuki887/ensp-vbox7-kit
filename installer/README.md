# installer/ —— 安装器说明

让原版华为 eNSP 运行在 VirtualBox 7.x 上。eNSP 和 VirtualBox 的安装位置都会自动检测，不需要手工改注册表或复制文件。

快速上手见仓库根目录的 [`README.md`](../README.md)；本文是各脚本的详细说明和排错手册。

## 目录内容

| 文件 | 作用 |
|------|------|
| `安装.bat` | 安装入口：部署垫片和补丁、注册基础设备 VM、运行环境检测 |
| `卸载.bat` | 卸载入口：还原版本号、插件、运行时，移除垫片 |
| `环境检查.bat` | 只读采集本机环境并生成报告；加 `-Fix` 执行修复 |
| `注册设备.bat` | 后备入口，只在安装时跳过了自动注册的情况下使用 |
| `清理残留.bat` | 结束没有退出的 `VBoxHeadless.exe` 残留进程 |
| `install_all.ps1` | 安装流程编排，由 `安装.bat` 调用：提权部署补丁，以登录账户身份注册设备，最后做环境检测 |
| `install.ps1` | 部署 / 卸载 / 检测，由 `install_all.ps1` 和 `卸载.bat` 调用 |
| `register_vms.ps1` | 注册基础设备 VM，由 `install_all.ps1` 和 `注册设备.bat` 调用 |
| `cleanup_orphans.ps1` | 清理残留进程，由 `清理残留.bat` 调用 |
| `diag.ps1` | 诊断与修复，由 `环境检查.bat` 调用；默认只读 |
| `fix.ps1` | 修复操作库，由 `diag.ps1` 和 `install.ps1` 引用 |
| `checks.ps1` | 只读探测库，由 `install.ps1`、`diag.ps1`、`fix.ps1` 共用 |
| `payload/VBox52.dll` | COM / vtable 垫片，部署到 eNSP 目录下的四个加载位置 |
| `payload/VAR_Plugin.dll` | 已补丁的 AR 插件（IVirtualBox 5.2 → 7.2 vtable 重映射）。**不随仓库分发**，安装时由 `tools\prepare-payload.ps1` 从本机 eNSP 生成 |
| `payload/msvcrt-x86/*.dll` | x86 VC++ 运行时，部署到 VirtualBox 的 `x86\` 子目录 |

## 使用

### 安装

前提：eNSP 和 VirtualBox 7.2.x 都已用各自的官方安装程序装好（本项目不包含这两者），并装有 Python 3（首次安装时
用来生成 `VAR_Plugin.dll`）。

用**平时启动 eNSP 的账户**双击 `安装.bat`。窗口里依次显示：

0. 若 `payload\` 下还没有 `VAR_Plugin.dll`，先从本机 eNSP 生成（只读取 eNSP 目录，不需要管理员权限）；
1. 安装前检查（只读）。查出的问题分三类：能自动修且无损的，安装时顺带修好；会短暂中断网络的，先说明影响再问你；
   没有自动修复手段的，问你是否继续；
2. 部署垫片、AR 插件补丁和 x86 运行时（需要管理员权限，弹一次 UAC）；
3. 注册基础设备 VM（以登录账户身份运行）；
4. 运行时环境检测，并执行检出的可修项。

结束后启动 eNSP，先单独启动一台 AR 验证。

整个流程最多弹两次 UAC：第一次用于部署补丁；第二次只在环境检测查出可修项时出现，没有可修项就不弹，也不改动系统。

### 环境检查（`环境检查.bat`）

只读采集本机环境，生成报告 `%ProgramData%\ensp-vbox-shim\diag-<时间戳>.txt`。报告可以原样附在 issue 里。

报告内容包括：系统版本与 build 号、四个垫片位置的哈希、CLSID 指向、host-only 网络各层状态、基础 VM 的注册状态与
`<VM>_Link` 快照、最近一次启动的 `VBox.log` 和 `VBoxHardening.log` 末尾。

**必须用启动 eNSP 的那个账户运行**。报告读取的是当前账户的 `%USERPROFILE%\.VirtualBox\`，换成别的账户，读到的内容与
eNSP 实际使用的不一致。

采集阶段不启动虚拟机、不修改系统设置。报告共 10 节，第 [9] 节列出检出的问题和对应的修复命令。修复用法：

```bat
环境检查.bat                     :: 只生成报告
环境检查.bat -Fix                :: 执行全部无损修复
环境检查.bat -Fix all            :: 连同需确认的修复一起执行，逐条确认
环境检查.bat -Fix firewall       :: 只执行指定项（id 见报告第 [9] 节）
环境检查.bat -Fix all -DryRun    :: 只列出计划，不执行
环境检查.bat -Fix all -Yes       :: 跳过逐条确认
```

- 修复需要管理员权限，脚本本身不会提权：请在“以管理员身份运行”的命令提示符中执行带 `-Fix` 的命令。
- 执行过的命令逐条回显，并记录到 `<报告名>.repair.txt`。
- 需确认的修复在读不到输入时（无人值守、输入被重定向）一律不执行；要跳过确认必须显式加 `-Yes`。
- 没有检出问题时第 [9] 节为空，`-Fix` 也不会修改任何设置。

### 注册设备（`注册设备.bat`）

`安装.bat` 默认会自动注册，正常流程不需要单独运行它。

只有一种情况会跳过自动注册：用“其他管理员账户”运行了安装（例如右键 → 以管理员身份运行，并在 UAC 里输入了另一个
账户）。这时进程身份和启动 eNSP 的用户不一致，注册会写进错误的用户配置，eNSP 读不到。安装窗口会对此给出提示。
处理方法：用启动 eNSP 的账户（不要提权）双击 `注册设备.bat`。

脚本扫描 `vboxserver\` 下的基础盘（`AR_Base`、`WLAN_*_Base`）：

- 未注册的，注册；
- 已注册且路径正确的，保持不动；
- 已注册但路径失效的，注销后重新注册（注销不带 `--delete`，不动磁盘内容）；
- 缺少 `<VM>_Link` 快照的，补建快照（VM 正在运行时跳过）。

这些基础设备 VM 是创建设备时的克隆源，没注册的话设备无法启动。操作可以重复执行。只想看看会做什么、不实际执行：

```powershell
powershell -ExecutionPolicy Bypass -File register_vms.ps1 -Check
```

注册阶段不提权。VM 注册写入当前用户的 `.VirtualBox\VirtualBox.xml`，这个文件必须属于启动 eNSP 的账户。
`install_all.ps1` 按此划分权限：补丁阶段提权，注册阶段使用登录账户身份。

### 需要导入设备包的设备

部分设备需要外挂磁盘镜像，镜像不随 eNSP 安装程序提供。判断依据：插件目录下有 `Database\` 子目录，且其中的模板指向
该目录下的镜像文件。全新安装时这些 `Database\` 都是空的。

| 插件目录 | 设备型号 | 镜像 | VM 模板 |
|---|---|---|---|
| `plugin\ngfw` | USG6000V | `Database\vfw_usg.vdi`（约 940 MB） | `tools\ngfw\vfw_usg_for_vbox5.0.vbox` |
| `plugin\svrp` | CE6800、CE12800 | `Database\CE.img` | `Tools\svrp\CE.xml` |
| `plugin\cx` | CX200 | `Database\CX.img` | `Tools\svrp\CX.xml` |
| `plugin\ne` | NE40E | `Database\NE40E.img` | `Tools\svrp\NE40E.xml` |
| `plugin\ne5ke` | NE5000E | `Database\NE5000E.img` | `Tools\svrp\NE5KE.xml` |
| `plugin\ne9k` | NE9000 | `Database\NE9000.img` | `Tools\svrp\NE9K.xml` |

七种设备对应六个包；CE6800 和 CE12800 共用 `CE.img`（`plugin\svrp` 下只有一份模板）。镜像放在各自插件的 `Database\`
下，文件名必须与模板中 `location="../../Database/..."` 的值一致，不能改名。本项目不附带任何镜像。

**导入方法**：启动这些设备时，eNSP 会弹出“导入设备包”对话框（提示文字为“请导入%s的设备包”，内置说明只以 USG6000V
为例，但对话框是通用的）。在“包路径”中填入镜像文件的完整路径，点“导入”，复制完成后再点一次启动。对话框只接受镜像
文件本身；拿到的是 zip 包时先解压。六种设备包都用这个方法，不需要额外脚本。

复制完成后的注册由 eNSP 和垫片完成：

- **CE / CX / NE40E / NE5000E / NE9000**：插件执行 `VBoxManage registervm "<插件>\Tools\svrp\<型号>.xml"`，再用
  `startvm <VM名> --type headless` 原地启动，不克隆、不建快照。
- **USG6000V**：插件使用链接克隆，需要已注册的 `vfw_usg` 和一个 `vfw_usg_Link` 快照。垫片在插件探测这台设备时自动
  完成注册和快照，随后 eNSP 执行 `clonevm vfw_usg --snapshot vfw_usg_Link ...`。

`vfw_usg.vdi` 约 940 MB，复制需要一两分钟，进度条走完后对话框自动关闭。

**资源需求**：CE / CX / NE40E / NE5000E / NE9000 直接启动 VM 本身，不克隆。它们的模板各分配 4 GB 内存，内存不足时系统
会大量换页，甚至整机无响应（实测在分配了 2 GB 的虚拟机里，一台 CE12800 就能让它失去响应）。模板各分配 1 个 vCPU，
嵌套虚拟化环境下启动明显变慢，NE 系列等大型设备可能超过十分钟。

**启动进度条**：这些设备是完整的虚拟机，同时启动多台时 eNSP 的进度条可能长时间不动，这不代表设备没在启动。可以双击
设备进入控制台确认，或检查 `plugin\<插件>\LogFile\infolog*.txt` 里是否出现 `CAgent::ST_STARTED`（设备进入运行状态的
标志）。启动过程中关闭 eNSP 会一并终止正在引导的设备。

### 设备关闭后的残留进程（CE / CX / NE 系列）

**现象**：关闭这些设备或关闭 eNSP 后，`VBoxHeadless.exe` 不立即退出，每个进程占用 1.2–1.5 GB 内存。设备图标可能显示
“异常退出”，或弹出 `VBoxHeadless.exe - 应用程序错误`（`0x...24 该内存不能为 read`）。

**2026-09-12 实测**：

- 关闭 eNSP 时，eNSP 对每台设备执行 `VBoxManage controlvm <VM名> poweroff`（硬断电）。
- 这些设备的系统是 Linux，硬断电后收尾很慢，实测超过五分钟才陆续退出，期间内存不释放。
- 部分进程在收尾时访问空指针崩溃，弹出“应用程序错误”对话框；对话框不关，进程就不释放内存。
- 全部退出后内存正常归还（实测从 18.0 GB 恢复到 24.8 GB），不是永久泄漏。

**处理**：

1. 出现“应用程序错误”对话框时，点“确定”关闭。
2. 或者运行 `清理残留.bat`。清理范围取决于 eNSP 是否在运行：
   - eNSP 已关闭：eNSP 设备的 `VBoxHeadless` 都算残留，列出后经你确认全部结束；
   - eNSP 运行中：只结束 VirtualBox 记录里已不在运行的孤儿进程，正在使用的设备不受影响。

   不属于 eNSP 的虚拟机一律不碰。脚本会先列出待清理的进程（含 VM 名和内存占用），确认后才执行。实测强制结束后
   VirtualBox 的记录会自动恢复，不会留下幽灵条目。

> 这是 VirtualBox 7.x 硬断电收尾时的行为，与垫片无关：垫片是 32 位的，只加载进 32 位的 eNSP 进程，而
> `VBoxHeadless.exe` 是 64 位的。分析见 [`docs/findings/svrp-shutdown-crash.md`](../docs/findings/svrp-shutdown-crash.md)。

### 卸载

运行 `卸载.bat`。它会：

- 把注册表里的 VirtualBox 版本号改回真实版本；
- 从 `.orig.bak` 还原 AR 插件（以及手工打过补丁的 NGFW 插件）；
- 还原或移除各处的 `VBox52.dll`：`tools\`、`plugin\ngfw\tools\ngfw\` 两处原本有华为的文件，还原为原版；eNSP 根目录、
  `vboxserver\` 两处是安装时新建的，直接删除；
- 还原或移除 VirtualBox `x86\` 子目录下的 VC++ 运行时。

CLSID 项需要手动处理，见下面的[卸载的最后一步](#卸载的最后一步clsid)。

### 只检测不改动

查看当前机器状态，不做任何修改：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -Check
```

输出内容：eNSP 和 VirtualBox 的路径、垫片 DLL 部署状态、注册表版本号、CLSID 指向、`VAR_Plugin.dll` 和 `NGFW_Plugin.dll`
的补丁状态，以及环境快照。

### 环境快照

安装和 `-Check` 时都会输出一段环境快照，内容是设备启动失败（error 40）的常见原因，只读不改：

- **CPU / VT-x**：固件虚拟化开关状态、VMX 扩展是否可用。启用 Hyper-V / WSL 时固件项通常显示“未启用”，这是 hypervisor
  接管了 VT-x，不是故障。
- **Hyper-V / WHP / 内存完整性（HVCI）/ 虚拟机平台**：任一项启用时，VirtualBox 7.x 会改用 WHP 后端。eNSP 原配的
  VirtualBox 5 与 Hyper-V 冲突、无法启动；7.x 能通过 WHP 与 Hyper-V / WSL / WSA 共存，代价是设备启动变慢（单台 3–5
  分钟）。这是后端差异，不是故障，不需要关闭 Hyper-V。
- **x86 VC++ 运行时**：`VBox\x86\` 下是否有 `VCRUNTIME140.dll` 和 `MSVCP140.dll`。缺失时报 `0x800700C1`，进而导致
  error 40；安装时会补上这两个文件。
- **版本伪装**：注册表 `Oracle\VirtualBox` 下 `Version` 和 `VersionExt` 的当前值。

快照同时写入安装日志 `%ProgramData%\ensp-vbox-shim\install.log`。

### 手动指定路径

自动检测失败时：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1 -EnspDir "D:\Program Files\Huawei\eNSP" -VBoxDir "D:\Program Files\Oracle\VirtualBox"
```

`安装.bat` 也接受同样的参数，会原样传下去。

## 安装做了什么

1. **部署垫片 DLL**：把 `payload\VBox52.dll` 写到 eNSP 的四个加载位置：`tools\`、`vboxserver\`、eNSP 根目录、
   `plugin\ngfw\tools\ngfw\`。每个位置先比对哈希：相同就跳过；不同则先把原文件备份为 `.orig.bak` 再覆盖（旧版垫片
   直接覆盖，不当作原文件备份）。
2. **写入版本伪装**：把 `HKLM\SOFTWARE\Oracle\VirtualBox` 的 `Version` 和 `VersionExt` 都改成 `5.2.44`（64 位视图和
   WOW6432Node 视图都写）。eNSP 启动时读 `VersionExt`（以 `KEY_WOW64_64KEY` 打开，即 64 位视图），版本不在 4.2–5.2 之间
   就拒绝运行。这个值**不能带构建号**：eNSP 读 `VersionExt` 时复用了 `InstallDir` 的缓冲区长度，`VersionExt` 一旦比
   `InstallDir` 长就会读取失败，报“未安装 VirtualBox”。
3. **重定向 CLSID InprocServer32**：把 32 位视图中 `CLSID\{B1A7A4F2-...}\InprocServer32` 的默认值指向 `tools\VBox52.dll`
   的实际路径（按 eNSP 安装位置生成）。eNSP 是 32 位进程，只读 32 位视图；64 位视图保持 VirtualBox 原样。
4. **替换 AR 插件**：用 `payload\VAR_Plugin.dll`（从本机 eNSP 生成的已补丁版本）覆盖 `plugin\ar1000v\VAR_Plugin.dll`，
   原文件备份为 `.orig.bak`。运行时不做字节补丁。
5. **部署 x86 VC++ 运行时**：把 `VCRUNTIME140.dll`、`MSVCP140.dll` 写到 VirtualBox 的 `x86\` 子目录。
6. **授予写权限**：给登录用户授予 `vboxserver\` 目录的修改权限（设备运行时要在这里写日志）。

原理详见 [`docs/architecture.md`](../docs/architecture.md)。

> `NGFW_Plugin.dll` 不在上述六步之内。2026-09-10 的 A/B 实测表明，原版和 22 处 vtable 补丁版的启动结果没有差别（失败
> 签名相差不到 1 毫秒），原版就能正常启动 USG6000V。补丁器保留在 `patches/` 下，安装器不修改这个文件；`-Check` 仍会报告
> 它的状态（原版 / 已打补丁）。

## 自动检测逻辑

**eNSP 目录**：读取卸载注册表中 DisplayName 含 `eNSP` 的项的 `InstallLocation`；找不到时依次尝试
`Program Files (x86)\Huawei\eNSP` 和 `Program Files\Huawei\eNSP`。两种来源都要求目录下有 `tools\` 子目录。

**VirtualBox 目录**：读取 `HKLM\SOFTWARE\Oracle\VirtualBox` 的 `InstallDir`（32 位和 64 位视图都试）；找不到时使用默认
安装路径。

任一项检测失败时，用 `-EnspDir` / `-VBoxDir` 指定。

## 卸载的最后一步（CLSID）

卸载脚本不修改 CLSID 项：它的原始状态随 VirtualBox 版本而异，猜错了可能破坏 VirtualBox 的 COM 注册。

实测原版 VirtualBox 7.2.16 的 32 位视图里**没有**这个键，VirtualBox 安装程序的“修复”也不会删除它。确认不再需要垫片后，
在管理员命令提示符中删除即可还原：

```bat
reg delete "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}" /f
```

如果安装前用 `reg export` 备份过这个键，也可以直接导入备份。其余各项（版本号、插件、垫片 DLL、运行时）由卸载脚本自动还原。

## 覆盖是可逆的

被替换的文件都先备份为 `原文件名.orig.bak`，卸载时由 `卸载.bat` 从备份恢复。

完整性保证：

1. 部署前校验 `payload\` 中每个文件的 SHA256，不符就停止；
2. 目标位置哈希已一致时不覆盖；
3. 覆盖完成后才记录成功。

## 排错

> 安装后设备无法启动时，先运行 `环境检查.bat` 生成报告。报告按层给出结论，比对照本节逐条排查更快。

**双击无反应 / 窗口一闪而过**：UAC 被拒绝了。重新双击 `安装.bat`（不要用右键菜单），在 UAC 窗口点“是”。用“右键 →
以管理员身份运行”并选择其他管理员账户会跳过自动注册，之后需要另外运行 `注册设备.bat`。

**提示“需要管理员权限”**：直接运行了 `install.ps1`。请改用 `安装.bat`。

**补丁阶段失败，提权窗口一闪而过**：看日志 `%ProgramData%\ensp-vbox-shim\install.log`。

**生成 VAR_Plugin.dll 失败**：

- “找不到 Python 3”：安装 Python 3 并勾选 “Add python.exe to PATH”，然后重新运行 `安装.bat`；
- “没有找到可识别的 VAR_Plugin.dll”：补丁器只支持 eNSP 1.3.00.100 自带的那个版本，请先重装 eNSP；
- “SHA256 与预期不符”：删除 `payload\VAR_Plugin.dll` 后重新运行 `安装.bat`，会重新生成。

**“未能自动定位 eNSP 安装目录”**：用 `-EnspDir` 指定。

**窗口中文乱码**：`.bat` 文件是 GBK 编码，并用 `chcp 936` 切换代码页。出现乱码通常是文件被其他编辑器以别的编码另存了。

**安装后 eNSP 仍报版本错误**：运行 `-Check`，确认注册表 `Version` 和 `VersionExt` 都是 `5.2.44`、CLSID 指向 `tools` 下
的 DLL。如果 eNSP 反过来报“未安装 VirtualBox”，检查 `VersionExt` 是否比 `InstallDir` 长。

**设备启动要 3–5 分钟**：后端差异，不是卡死。启用 WSL2 / Hyper-V 时，VirtualBox 7.x 无法直接使用 VT-x，运行在 Hyper-V
之上，启动会变慢。

**设备启动报 error 40**：看安装日志开头的环境快照，或重新运行 `-Check`。安装器能处理的原因有：`VBox\x86\` 缺少 x86
运行时（`0x800700C1`）、`vboxserver\` 写权限不足（`VERR_FILE_NOT_FOUND`）、版本伪装没写入。启用 Hyper-V / WSL / WSA
不会导致 error 40：VirtualBox 7.x 会改走 WHP 后端，代价只是启动变慢。

**升级 VirtualBox 后报 error 40，垫片日志也没有异常**：检查 VirtualBox 的 host-only 网络。它有两类独立的故障，现象
相近，但处理方法不通用（D1 的方法对 D2 无效）。

**D1：host-only 过滤驱动绑定失效（网卡存在）**。eNSP 的命令日志 `eNSP\vboxserver\log\VBoxManage.log` 中出现以下内容
即为 D1：

```
Failed to open/create the internal network
'HostInterfaceNetworking-VirtualBox Host-Only Ethernet Adapter' (VERR_INTNET_FLT_IF_NOT_FOUND)
Failed to attach the network LUN (VERR_INTNET_FLT_IF_NOT_FOUND)
```

此时“网络连接”里有 VirtualBox Host-Only Ethernet Adapter（状态为已启用），`VBoxDrvInst.exe list` 也能列出
`VBoxNetAdp6` / `VBoxNetLwf`，但绑定已经失效。这与垫片无关：`findMachine` / `clonevm` / `modifyvm` 都成功了，失败发生在
随后的 `startvm`，VirtualBox 因无法创建 host-only 网络而拒绝启动。

处理：

1. 控制面板 → 网络连接 → 右键 VirtualBox Host-Only Ethernet Adapter → 禁用，等几秒再启用；
2. 在任务管理器中结束 `VBoxSVC.exe` 和 `VBoxSDS.exe`（会自动重启），然后完全关闭并重新打开 eNSP。

仍然无效时，确认网卡属性中 “VirtualBox NDIS6 Bridged Networking Driver” 处于勾选状态。

**D2：host-only 网络驱动包没有注册（网卡不存在）**。“网络连接”里没有 VirtualBox Host-Only Ethernet Adapter；
`VBoxDrvInst.exe list` 列不出任何 VirtualBox 驱动包；`VBoxManage hostonlyif create` 报：

```
Could not find Host Interface Networking driver! Please reinstall
```

D1 的“禁用再启用”对 D2 无效（没有网卡可以禁用，也没有绑定可以刷新），必须先安装驱动包，而且顺序不能颠倒：

```
VBoxDrvInst.exe install --inf-file "<VBoxDir>\drivers\network\netadp6\VBoxNetAdp6.inf"
netcfg.exe -v -l "<VBoxDir>\drivers\network\netlwf\VBoxNetLwf.inf" -c s -i oracle_VBoxNetLwf
```

第 2 条只能用 `netcfg.exe`：对 NDIS 过滤驱动，`VBoxDrvInst install` 只把驱动包放进驱动库，不会创建网络服务组件。两条
都装好后，把网卡禁用再启用一次，然后执行 `VBoxManage hostonlyif create`，用 `ipconfig` 核对地址，并重建 DHCP 服务器。
`环境检查.bat -Fix all` 可以自动完成这一整套操作（需先关闭 eNSP；会短暂中断网络，执行前会征得确认）。

> **不报错的失败**：只装了第 1 条（`netadp6`）没装第 2 条（`netlwf`）时，`hostonlyif create` 会成功，但网卡被命名为
> `VirtualBox Host-Only Ethernet Adapter #2`。eNSP 的设备模板按精确名称绑定，认不出带 `#2` 的名字，现象与“驱动没装”
> 一样。

可以用报错消失的顺序判断进度：装好 `netadp6` 后，`hostonlyif create` 的 `Could not find Host Interface Networking driver!`
和 VBoxSVC 日志里的 `HostWrap: ... could not be found` 消失；装好 `netlwf` 后，`VERR_INTNET_FLT_IF_NOT_FOUND` 消失。

**预防**：升级或重装 VirtualBox 后，先建一台带 host-only 网卡的虚拟机启动一下，确认网络正常，再启动 eNSP。安装包不完整
（手工解包、绿色版）是 D2 的常见原因。完整诊断记录见 [`docs/troubleshooting-error40.md`](../docs/troubleshooting-error40.md)
根因 D1 / D2。

**设备启动报 error 40，绕开 eNSP 直接 `VBoxManage startvm` 也失败**：VirtualBox 的进程加固没能创建 VM 子进程。
`VBoxHardening.log` 末尾是 `Error -104 in supR3HardenedWinReSpawn! (enmWhat=5)`，日志里没有被拒绝的模块，诊断报告里
“被拒的模块”一项也为空。

判断依据有三条：绕开 eNSP 直接启动也失败；加固日志的错误码是 `-104` 而不是 `-5657`；报告里没有被拒的模块。`-5657` 是
加固拒绝了某个具体文件，可以卸载对应软件；`-104` 是 `CreateProcessW` 本身没成功，失败发生在加载任何模块之前，没有
可卸载的对象。

这个问题**偶发，与 Windows build 无关**：2026-08 的更新后出现，2026-09 的累积更新后消失，三天后又在同一 build
（`26200.9457`）上复发。与 eNSP 和垫片都无关。

失败时 VM 根本没启动，没有副作用：**再点一次“启动”即可。** 垫片在这里帮不上忙：`-104` 发生在 `VBoxHeadless.exe` 自己的
加固重启链里，和垫片不在同一个进程。完整诊断记录见 [`docs/troubleshooting-error40.md`](../docs/troubleshooting-error40.md)
根因 E。

**在 Windows 沙盒 / WDAG 中报 error 40**：不支持，也无法修复。Windows 沙盒通过 VSMB 挂载系统盘（`\Device\vmsmb\...`），
而 VirtualBox 的进程加固要求 `kernel32.dll` / `ntdll.dll` 从普通磁盘卷（`\Device\HarddiskVolume`）加载，两者冲突，VM 进程
在启动阶段就被加固机制终止（`VBoxHardening.log` 记录 `rc=-5632` / `rc=-610`）。这是 Windows 沙盒与 VirtualBox 之间的固有
冲突，原版 VirtualBox 在沙盒里同样无法启动。请改用普通虚拟机或物理机。

## 已知限制：嵌套虚拟化

在虚拟机里运行本项目时（宿主机启用 Hyper-V，在 Win10 / Win11 虚拟机里运行 eNSP，共三层嵌套），网络设备可能显示
“正在运行”，但不输出 `####` 进度条，也进不了 `<Huawei>` 命令行。

原因：虚拟机里的 VirtualBox 拿到裸 VT-x 时会选择原生 HM（unrestricted guest）后端，而在二级嵌套下，这个后端运行 VRP
32 位内核从实模式切到分页的早期引导有缺陷，设备内核在固定地址 panic（`c013e501`）。关键在于 VT-x 归谁、选了哪个后端，
而默认行为由虚拟机里的系统决定：Win10 默认暴露 VT-x，选原生 HM，崩溃；Win11 报告 VT-x 不可用，回退到 NEM，正常。
所以这个问题只出现在 Win10 虚拟机里。

处理方法（在虚拟机内执行，需要管理员权限）：

```powershell
# 启用 Windows 虚拟机监控程序平台（WHP），让 VirtualBox 拿不到裸 VT-x，从而回退到 NEM
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
# 然后重启虚拟机
```

WHP 是全局的后端选择，重启后新克隆的设备都会自动使用 NEM，不需要逐台设置 `UseNEMInstead`。只有 VT-x 对 VirtualBox 仍然
可见时，才需要补充：

```powershell
VBoxManage setextradata <vm> "VBoxInternal/HM/UseNEMInstead" "1"
```

判断与验证细节见 [`docs/troubleshooting-error40.md`](../docs/troubleshooting-error40.md) 根因 C。

物理机（非嵌套）不受此限制。

## 系统要求

- Windows，使用系统自带的 Windows PowerShell 5.1；
- 已安装原版 eNSP 和官方 VirtualBox 7.2.x；
- Python 3（首次安装时生成 `VAR_Plugin.dll`）；
- 管理员权限（`.bat` 会自动申请）。

遇到问题请先运行 `环境检查.bat`，再把报告附在 [issue](https://github.com/satsuki887/ensp-vbox7-kit/issues) 里。
