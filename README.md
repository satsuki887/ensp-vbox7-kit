# ensp-vbox7-kit

让原版**华为 eNSP** 稳定运行在 **VirtualBox 7.2** 上：COM 垫片、一键安装器、环境诊断与修复工具，以及一组排障记录。

> **本项目基于 [LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim) 二次开发。**
> 核心设计和绝大部分逆向成果出自原作者 **LBXaaa**，原项目的提交历史完整保留在本仓库中。
> 详见下文[致谢](#致谢)与 [`NOTICE.md`](NOTICE.md)。
>
> 本项目免费开源。若是付费获得，则为他人倒卖。

![eNSP 在 VirtualBox 7.2 上运行](docs/images/ensp-running-on-vbox72.png)

<sub>截图来自原作者：VirtualBox 7.2.8 与 Hyper-V 共存，eNSP 交换机互 ping 正常。</sub>

## 它解决什么问题

eNSP 只认 VirtualBox 5.2，而 5.2 在新版 Windows 上装不上、不稳定，甚至会蓝屏。原项目的做法是：对 eNSP
伪装成 5.2，再把它的调用翻译给真正的 VirtualBox 7.2（原理见 [`docs/architecture.md`](docs/architecture.md)，
原 README 存档于 [`docs/upstream/README.md`](docs/upstream/README.md)）。

本仓库在原项目基础上：

- **修复**了垫片和安装器里几处会导致崩溃或漏改参数的问题：多台设备同时启动、Windows 兼容模式、日志溢出、
  64 位 COM 注册、升级安装；
- **不再分发**华为的 `VAR_Plugin.dll`，改为在安装时从你本机的 eNSP 生成；
- **修复**了 CE / CX / NE 系列关机卡死并崩溃的问题（根因在 VirtualBox 7 的 virtio 网卡，安装器自动规避）；
- 提供补丁器，让 **Cloud 设备在 Npcap 下**也能绑定本机网卡（可选）；
- 加入**可复现编译**和一组**测试 / 探针工具**；
- 记录了排障过程，以及一处已定位、尚未修复的问题（见[已知问题](#已知问题与后续计划)）。

完整改动见 [`CHANGELOG.md`](CHANGELOG.md)。

## 已验证的环境

| 项目 | 版本 |
|---|---|
| Windows | 11 家庭版 build 26300（eNSP 设为“Windows 7 兼容 + 以管理员身份运行”） |
| CPU | Intel i9-13900HX（未开 Hyper-V / VBS） |
| eNSP | V100R003C00SPC100（1.3.00.100） |
| VirtualBox | 7.2.16 r174877 |
| 抓包驱动 | WinPcap 4.1.3 + Npcap 1.89（**非**兼容模式） |
| 已测设备 | AR2220、S5700、USG6000V、AC、CE6800、NE40E、NE9000；5 台同时启动；Cloud、接口抓包 |

开启 WSL2 / Hyper-V 的机器也能用（原作者测过），但 VirtualBox 会改走 Hyper-V 后端，设备启动明显变慢。

## 安装

**准备**

- 关闭 eNSP 和 VirtualBox，备份拓扑文件（`.topo`）。
- 安装 [Python 3](https://www.python.org/downloads/windows/)（勾选 “Add python.exe to PATH”）。首次安装时要用它从
  本机 eNSP 生成 `VAR_Plugin.dll`。
- 各安装包的官方下载地址与校验值见 [`docs/dependencies.md`](docs/dependencies.md)。

**步骤**

1. 卸载旧版 VirtualBox（如 5.2.44），然后**重启**。
2. 安装 VirtualBox 7.2.16，选项保持默认。
3. 下载本仓库（`git clone` 或 GitHub 上的 “Download ZIP”），用**平时启动 eNSP 的账户**双击
   `installer\安装.bat`。安装器会依次：
   - 做一遍安装前检查（只读）。会影响网络的修复项，执行前会先征得你同意；
   - 部署垫片和补丁，并修正 CE / NE 系列虚拟机的网卡设置（此时弹一次 UAC，点“是”）。被替换的原文件都备份为 `.orig.bak`；
   - 注册 eNSP 的基础设备 VM；
   - 运行一次环境检测，并把报告保存到 `C:\ProgramData\ensp-vbox-shim\`。
4. 启动 eNSP，先单独启动一台 AR 试试。

**升级**：拉取新版本后重新运行 `安装.bat`，旧版垫片会被自动替换。

## installer\ 下的工具

| 脚本 | 什么时候用 |
|---|---|
| `安装.bat` | 首次安装、升级 |
| `环境检查.bat` | 设备起不来时先跑它。生成一份只读报告，第 [9] 节列出问题和修复命令；加 `-Fix` 执行修复 |
| `清理残留.bat` | 关闭 eNSP 后仍有 `VBoxHeadless.exe` 没退出、占着内存（兜底用，正常情况下用不到） |
| `注册设备.bat` | 只在安装时提示“已跳过自动注册”时使用 |
| `卸载.bat` | 还原 eNSP 和 VirtualBox 的改动 |

每个脚本的细节、排错方法以及需要导入设备包的设备（USG6000V、CE、NE 等）见 [`installer/README.md`](installer/README.md)。

## 日常使用须知

- **CE / CX / NE 系列**：在 eNSP 里“停止设备”只停掉虚拟机里的路由器，虚拟机本身要到**关闭 eNSP** 时才关机。
  安装器修正网卡设置后，关机在 1 秒内完成；以前要卡约 3 分钟并弹出 `VBoxHeadless.exe` 应用程序错误
  （原因见 [`svrp-shutdown-crash.md`](docs/findings/svrp-shutdown-crash.md)）。**重装 eNSP 后要重新运行 `安装.bat`**，
  否则这项修正会被原版配置覆盖掉。
- **CE / NE 一直显示 `###` 后报启动超时**：多半是有一个普通权限的 `VBoxSVC.exe` 在运行（例如刚用过 VirtualBox
  管理器或命令行）。关闭 eNSP，在任务管理器里结束 `VBoxSVC.exe`，再重新打开 eNSP。
- **内存**：CE / NE 每台约占 4 GB。16 GB 内存的机器如果还开着 VMware，这类大设备尽量只开一两台。
- **抓包驱动**：推荐保留 WinPcap 4.1.3，安装 Npcap 时**不要**勾选 “WinPcap API-compatible Mode”。只想用 Npcap 的话，
  先关闭 eNSP、以管理员运行 `python patches\patch_pcap_version.py`，否则 Cloud 设备只剩 UDP
  （见 [`cloud-npcap.md`](docs/findings/cloud-npcap.md)）。
- **升级或重装 VirtualBox 之后**：它会在所有网卡上重新启用 “VirtualBox NDIS6 Bridged Networking Driver”。
  eNSP 用不到物理网卡上的这一项，可以在无线网卡上关掉；**host-only 网卡上的那一项必须保留**。

## 卸载与回滚

- 运行 `installer\卸载.bat`：还原 VirtualBox 版本号、`VAR_Plugin.dll`、x86 运行时、各处的 `VBox52.dll`
  和 CE / NE 系列的网卡设置，删除安装器新建的文件。
- 打过 Cloud 补丁的，用 `python patches\patch_pcap_version.py --restore` 还原（卸载.bat 不处理它）。
- **COM 注册表项需要手动处理**。原版 7.2.16 的 32 位注册表视图里根本没有 `CLSID_VirtualBox` 这个键，
  所以“修复 VirtualBox”也删不掉它。确认不再需要垫片后，在管理员命令提示符中执行：

  ```bat
  reg delete "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}" /f
  ```

  稳妥起见，可以在安装前先用 `reg export` 备份这个键。
- **退回 VirtualBox 5.2**：7.2 会把 eNSP 基础虚拟机的 `.vbox` 配置升级成新格式，5.2 读不了。回滚前要还原安装前
  备份的 `eNSP\vboxserver\**\*.vbox` 和 `%USERPROFILE%\.VirtualBox\VirtualBox.xml`。

## 已知问题与后续计划

| 问题 | 状态 | 记录 |
|---|---|---|
| IVirtualBox 方法区槽位整体少算 12（影响 `VAR_Plugin` 补丁、代理方法区、IMachine 映射） | 已确认；AR 实际可用 | [`vtable-reserved-slots.md`](docs/findings/vtable-reserved-slots.md) |
| Cloud 设备不支持 Npcap 兼容模式 | **已修复**：补丁器 `patches/patch_pcap_version.py`（版本号 + 速率过滤，已在 eNSP 内验证；不在安装器内） | [`cloud-npcap.md`](docs/findings/cloud-npcap.md) |
| CE / NE 关机卡 60 秒后 `VBoxDD.DLL` 崩溃；旧实例未退出时重开导致插件卡死 | **已修复**：根因为 VirtualBox virtio-net 对未连接网卡的 bug，安装器第 7 步规避（CE / NE 已在 eNSP 内回归） | [`svrp-shutdown-crash.md`](docs/findings/svrp-shutdown-crash.md) |
| VirtualBox 5.2.44 导致 0xD1 蓝屏 | **已解决**（本项目的起点） | [`bsod-vbox52.md`](docs/findings/bsod-vbox52.md) |

遇到问题请先运行 `installer\环境检查.bat`，再把生成的报告附在
[issue](https://github.com/satsuki887/ensp-vbox7-kit/issues) 里。

## 开发

```bat
build\build.bat                       :: 编译 VBox52.dll（自动查找 VS；没装 SDK 时用 local\toolchain）
build\build.bat selftest              :: 带测试导出的版本，只供测试，切勿发布
tools\dev\hooktest\run.bat            :: CreateProcessW hook 并发 + 兼容层矩阵测试
tools\dev\vboxprobe\run.bat           :: 读出已安装 VirtualBox 的真实虚表布局（每次升级 VirtualBox 后先跑）
tools\dev\pcapprobe\run.bat           :: 像 Cloud 插件一样调用 packet.dll，对比 WinPcap / Npcap
tools\dev\pcapprobe\cloud.bat         :: 直接调用 Cloud 插件的网卡枚举，看 WinPcap / Npcap 下各列出哪些网卡
powershell -Command ". .\build\tests\harness.ps1; . .\installer\checks.ps1; . .\build\tests\checks.Tests.ps1"  :: 检测库单元测试
powershell -File tools\dev\installer-tests\test_deploy.ps1   :: 安装器升级 / 卸载逻辑沙箱测试
powershell -File tools\dev\installer-tests\test_svrp_nic.ps1 :: 安装器第 7 步（CE / NE 网卡）沙箱测试，需 VirtualBox
```

修改 `src/` 之后：编译 → 把 `build\VBox52.dll` 复制到 `installer\payload\` → 在 `installer\install.ps1` 中把旧的
`DLL_SHA256` 移入 `PREV_DLL_SHA256`，再填入新哈希 → 跑 hooktest 和 test_deploy。

上游有更新时合并：

```bat
git fetch upstream
git merge upstream/main
```

`local/` 目录（git 忽略）存放安装包、备份、崩溃现场和编译用的 SDK 包，说明见 [`local/README.md`](local/README.md)。

## 目录结构

```
src/                 垫片源码（C++ / MASM）
build/               build.bat 与发布用的 VBox52.dll；tests/ 是检测库的单元测试
installer/           安装 / 卸载 / 注册设备 / 环境检查 / 清理残留
  payload/           安装器部署的文件（VAR_Plugin.dll 在本机生成，不进 git）
patches/             VAR_Plugin / NGFW 插件补丁器，Cloud + Npcap 补丁器
registry/            参考用 .reg（安装器直接写注册表，不导入它们）
tools/               prepare-payload.ps1；dev/ 下是测试与探针工具
docs/                架构、vtable 映射、诊断说明；findings/ 是本仓库的排障记录；upstream/ 是原 README
analysis/            原作者的逆向分析脚本与输出
local/               本机专属，git 忽略
```

## 致谢

- **[LBXaaa](https://github.com/LBXaaa)** —— [ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim) 的作者。
  COM 垫片、vtable 映射、版本伪装、AR 插件补丁、安装 / 诊断 / 修复工具链，以及大量真机逆向与实测，都是本项目
  得以存在的基础。原项目的 155 次提交完整保留在本仓库历史中。介绍文章：
  <https://developer.aliyun.com/article/1739948>
- 本仓库的部分排障、修复与测试是在 AI 助手 Claude（Anthropic）协助下完成的，相关提交带有
  `Co-Authored-By` 标记。
- eNSP 归华为技术有限公司，VirtualBox 归 Oracle，WinPcap 归 Riverbed，Npcap 归 Nmap Software LLC。

## 法律声明

> 以下为本项目的立场说明，**不构成法律意见**。不同国家和地区的法律不同，请使用者自行确认并遵守当地法律。

1. **许可证**：本仓库代码以 **Mozilla Public License 2.0** 发布（见 [`LICENSE`](LICENSE)）。来自原项目的文件及其
   修改版本，版权归原作者及各贡献者；再分发时须以 MPL-2.0 提供源代码，并保留原有的版权与许可声明。
   随附的 Microsoft Visual C++ 运行时不适用 MPL-2.0，版权归 Microsoft。详见 [`NOTICE.md`](NOTICE.md)。
2. **无隶属关系**：本项目与华为、Oracle、Nmap Software、Riverbed、Microsoft 均无任何隶属、合作或认可关系。
   文中提及的产品名称均为其权利人的商标或注册商标，仅用于说明兼容性。
3. **不分发第三方软件**：本仓库不包含、也不分发 eNSP、VirtualBox、WinPcap、Npcap 的安装程序或主程序，
   也不包含华为的插件文件；需要修改的插件由使用者用自己合法取得的副本在本机生成。使用者应自行合法取得上述软件，
   并遵守各自的许可条款（例如 Npcap 的免费许可对使用范围有限制，且禁止未经授权的再分发；以其许可证原文为准）。
4. **互操作与逆向分析**：本项目对相关软件的分析，仅以实现 eNSP 与新版 VirtualBox 之间的互操作为目的，
   不涉及绕过授权、破解收费功能或提取他人程序用于其他用途。相关法律中有关于"为学习研究软件设计思想与原理"
   或"为实现互操作"而分析软件的规定，例如中国《计算机软件保护条例》第十七条、欧盟第 2009/24/EC 号指令
   第 6 条、美国 17 U.S.C. §1201(f)；能否适用于具体情形，取决于当地法律和实际用途。
5. **无担保**：本项目按"原样"提供，不提供任何明示或默示的担保（MPL-2.0 第 6、7 条）。安装器会修改注册表和
   `Program Files` 下的文件；请在使用前备份，风险自负。用于考试或比赛时，请遵守主办方关于软件环境的规定。

## 许可证

[MPL-2.0](LICENSE)
