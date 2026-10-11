# ensp-vbox7-kit

让原版 **华为 eNSP** 稳定运行在 **VirtualBox 7.2** 上的一整套工具：COM 垫片、安装器、诊断与测试工具，
以及排障记录。

> **本项目基于 [LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim) 二次开发**，
> 核心设计与绝大部分逆向成果出自原作者 **LBXaaa**，本仓库完整保留了原项目的提交历史。
> 详见下文[致谢](#致谢)与 [`NOTICE.md`](NOTICE.md)。
>
> 本项目免费开源。若是付费获得，则为他人倒卖。

## 和原项目的关系

原项目解决了"eNSP 只认 VirtualBox 5.2，而 5.2 在新系统上装不上或不稳定"的问题：对 eNSP 伪装成 5.2，
把调用翻译给真正的 7.2（原理见 [`docs/architecture.md`](docs/architecture.md)、原 README 存档
[`docs/upstream/README.md`](docs/upstream/README.md)）。

本仓库在此基础上：

- **修复**了垫片和安装器中几处会导致崩溃或漏改参数的问题（多台设备同时启动、Windows 兼容模式、日志溢出、
  64 位 COM 注册、升级安装）；
- **不再分发**华为的 `VAR_Plugin.dll`，改为从你自己的 eNSP 现场生成；
- 加入**可复现编译**和一组**测试 / 探针工具**；
- 记录了几处新定位但尚未修复的问题，作为后续工作的起点。

完整列表见 [`CHANGELOG.md`](CHANGELOG.md)。上游有更新时可以合并：

```bat
git fetch upstream
git merge upstream/main
```

## 已验证的环境

| 项目 | 版本 |
|---|---|
| Windows | 11 家庭版 build 26300（eNSP 设为"Windows 7 兼容 + 以管理员身份运行"） |
| CPU | Intel i9-13900HX（未开 Hyper-V / VBS） |
| eNSP | V100R003C00SPC100（1.3.00.100） |
| VirtualBox | 7.2.16 r174877 |
| 抓包驱动 | WinPcap 4.1.3 + Npcap 1.89（**非**兼容模式） |
| 已测设备 | AR2220、S5700、USG6000V、AC、CE6800、NE40E、NE9000；5 台同时启动；Cloud、接口抓包 |

开着 WSL2 / Hyper-V 的机器，原项目作者也测过，VirtualBox 会走 Hyper-V 后端，设备启动明显变慢。

## 安装

准备：关闭 eNSP 和 VirtualBox，备份拓扑文件（`.topo`），装好 Python 3。各安装包的官方来源与校验值见
[`docs/dependencies.md`](docs/dependencies.md)。

1. 卸载旧版 VirtualBox（如 5.2.44），**重启**。
2. 安装 VirtualBox 7.2.16（选项默认）。
3. 双击 `installer\安装.bat`，UAC 点"是"：
   - 安装包里没有 `VAR_Plugin.dll` 时，会先用 `tools\prepare-payload.ps1` 从本机 eNSP 生成（无需管理员）；
   - 安装前检查是只读的；会影响网络的修复项会先征得你同意；
   - 原文件全部备份为 `.orig.bak`。
4. 启动 eNSP，先单独启动一台 AR 试试。

升级到新版本：拉取后重新运行 `安装.bat` 即可，会自动替换旧版垫片。

## 日常使用须知

- **CE / CX / NE 系列关闭需要约 3 分钟**，关闭后还可能弹出 `VBoxHeadless.exe` 应用程序错误，点"确定"即可
  （原因见 [`svrp-shutdown-crash.md`](docs/findings/svrp-shutdown-crash.md)）。在它们退出前**重开同一种设备**
  会让插件卡在 `###`。换拓扑时按这个顺序：**关闭 eNSP → `installer\清理残留.bat` → 重开 eNSP**。
- **内存**：CE / NE 每台约 4 GB。16 GB 内存的机器同时开着 VMware 时，大设备尽量只开一两台。
- **抓包驱动**：保留 WinPcap 4.1.3，Npcap **不要**勾选 "WinPcap API-compatible Mode"，否则 Cloud 设备只剩 UDP
  （[`cloud-npcap.md`](docs/findings/cloud-npcap.md)）。
- **升级或重装 VirtualBox 之后**：它会在所有网卡上重新启用 "VirtualBox NDIS6 Bridged Networking Driver"。
  eNSP 不需要物理网卡上的这一项，可以在无线网卡上关掉；**host-only 网卡上的那项必须保留**。

## 卸载与回滚

- `installer\卸载.bat`：还原版本号、`VAR_Plugin.dll` 和各处 `VBox52.dll`，删除安装器新建的文件。
- **COM 注册表项不会自动还原**。原版 7.2.16 的 `CLSID_VirtualBox` 在 32 位视图里根本没有这个键，
  所以"修复 VirtualBox"并不能删掉它；请对照安装前导出的注册表手工处理（建议安装前先用
  `reg export` 备份 `HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}`）。
- **退回 VirtualBox 5.2**：7.2 会把 eNSP 基础虚拟机的 `.vbox` 配置升级成新格式，5.2 读不了。
  回滚前要还原安装前备份的 `eNSP\vboxserver\**\*.vbox` 和 `%USERPROFILE%\.VirtualBox\VirtualBox.xml`。

## 已知问题与后续计划

| 问题 | 状态 | 记录 |
|---|---|---|
| IVirtualBox 方法区槽位整体少算 12（影响 `VAR_Plugin` 补丁、代理方法区、IMachine 映射） | 已确认，AR 实际可用 | [`vtable-reserved-slots.md`](docs/findings/vtable-reserved-slots.md) |
| Cloud 设备不支持 Npcap 兼容模式 | 根因已定位，有 2 字节补丁方案待验证 | [`cloud-npcap.md`](docs/findings/cloud-npcap.md) |
| CE / NE 关机时 `VBoxDD.DLL` NAT 线程崩溃；旧实例未退时重开导致插件卡死 | 可稳定复现，原因已定位 | [`svrp-shutdown-crash.md`](docs/findings/svrp-shutdown-crash.md) |
| VirtualBox 5.2.44 导致 0xD1 蓝屏 | **已解决**（本项目的起点） | [`bsod-vbox52.md`](docs/findings/bsod-vbox52.md) |

## 开发

```bat
build\build.bat                       :: 编译 VBox52.dll（自动找 VS；无 SDK 时用 local\toolchain）
build\build.bat selftest              :: 带测试导出的版本，只给测试用，切勿发布
tools\dev\hooktest\run.bat            :: CreateProcessW hook 并发 + 兼容层矩阵测试
tools\dev\vboxprobe\run.bat           :: 读出已安装 VirtualBox 的真实虚表布局（每次升级 VirtualBox 后先跑）
tools\dev\pcapprobe\run.bat           :: 像 Cloud 插件一样调用 packet.dll，对比 WinPcap / Npcap
powershell -File tools\dev\installer-tests\test_deploy.ps1   :: 安装器升级 / 卸载逻辑沙箱测试
```

修改源码后：编译 → 把 `build\VBox52.dll` 复制到 `installer\payload\` → 更新 `installer\install.ps1` 中的
`DLL_SHA256`，并把旧哈希移入 `PREV_DLL_SHA256`。

`local/` 目录（git 忽略）存放安装包、备份、崩溃现场和编译用的 SDK 包，说明见 [`local/README.md`](local/README.md)。

## 目录结构

```
src/                 垫片源码（C++ / MASM）
build/               build.bat 与发布用的 VBox52.dll
installer/           安装 / 卸载 / 注册设备 / 环境检查 / 清理残留
  payload/           安装包内容（VAR_Plugin.dll 本地生成，不进 git）
patches/             VAR_Plugin / NGFW 插件补丁器
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
