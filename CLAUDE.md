# CLAUDE.md —— ensp-vbox7-kit 维护说明

让原版华为 eNSP 运行在 VirtualBox 7.2 上的 COM 垫片 + 安装器 + 诊断工具。派生自
[LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim)（remote `upstream`，完整历史保留在本仓库），
MPL-2.0。本机专属信息见 `CLAUDE.local.md`（git 忽略，可能不存在）。

## 硬性规则

- **绝不提交第三方受版权保护的二进制**：华为的 `VAR_Plugin.dll` / `NGFW_Plugin.dll` / 任何 eNSP 文件，
  VirtualBox / WinPcap / Npcap / eNSP 安装包。`VAR_Plugin.dll` 由 `tools/prepare-payload.ps1` 本地生成。
  唯一例外是沿袭上游的 `installer/payload/msvcrt-x86/`（微软可再发行组件），见 `NOTICE.md`。
- `local/` 只放本机材料（安装包、备份、崩溃现场、SDK 包），除 `local/README.md` 外全部忽略。
  **不要运行 `git clean -X` / `-x`**：会删掉 `local/` 和已生成的 `VAR_Plugin.dll`。
- 保留原作者署名与 MPL-2.0 声明；新增文件同样用 MPL-2.0。`README.md` 的"致谢"和"法律声明"、`NOTICE.md` 不要删减。
- `build/selftest/` 是带测试导出 `ShimSelfTest_InstallHooks` 的构建，**永远不能进 payload 或发布**。

## 构建与测试

```bat
build\build.bat                    :: release，输出 build\VBox52.dll（/Brepro，可复现）
build\build.bat selftest           :: 测试版 -> build\selftest\VBox52.dll
tools\dev\hooktest\run.bat         :: hook 并发 + AppCompat 矩阵，必须 ALL PASSED
tools\dev\vboxprobe\run.bat        :: 真实虚表布局；升级 VirtualBox 后先跑它再信任任何槽位表
tools\dev\pcapprobe\run.bat        :: packet.dll 返回值（Cloud / Npcap 相关）
tools\dev\pcapprobe\cloud.bat      :: 直接调用 Cloud 插件的网卡枚举（WinPcap / Npcap 各跑一次）
powershell -Command ". .\build\tests\harness.ps1; . .\installer\checks.ps1; . .\build\tests\checks.Tests.ps1"  :: 检测库单元测试，须 ALL PASS
powershell -File tools\dev\installer-tests\test_deploy.ps1   :: 安装器升级/卸载逻辑
powershell -File tools\dev\installer-tests\test_svrp_nic.ps1 :: 第 7 步 SVRP 网卡改挂（建临时 VM，需 VirtualBox）
```

`tools/dev/vsenv.bat` 用 vswhere 找 VS（`VCVARS` 可覆盖），没装 Windows SDK 时解压 `local/toolchain/*.nupkg`。

**改了 `src/` 之后发布 DLL 的流程**：`build.bat` → 复制 `build\VBox52.dll` 到 `installer\payload\` →
`installer\install.ps1` 里把旧 `DLL_SHA256` 移进 `PREV_DLL_SHA256`、填入新哈希 → 跑 hooktest 与 test_deploy。
`build/VBox52.dll` 和 `installer/payload/VBox52.dll` 必须是同一份文件。

## 必须知道的技术事实（详见 `docs/findings/`）

- eNSP 是 32 位进程，`CLSID_VirtualBox` 只写 `WOW6432Node` 视图；64 位视图保持 VirtualBox 原样。
- eNSP 常带 AppCompat 层（`~WIN7RTM RUNASADMIN`），其中 `GetProcAddress` 返回 shim 包装；
  需要真实地址时自己解析导出表（见 `find_export`）。
- VirtualBox 7.2 的 IVirtualBox 方法区从槽位 **48** 开始（36–47 是 12 个保留属性）。`src/vbox52_thunks.asm`
  方法区、`wrap_*`、`patches/patch_var_plugin.py` 仍按少 12 的旧表，属已知问题，修改前读
  `docs/findings/vtable-reserved-slots.md`。
- 抓包驱动：WinPcap 4.1.3 + Npcap **非兼容模式**。Cloud 插件和 eNSP_Client 按 `PacketGetVersion()[0]=='4'`
  选解析方式，并丢弃 `LinkSpeed < 10 Mbps` 的网卡，而 Npcap 对所有网卡都报 0；
  `patches/patch_pcap_version.py` 两处都改（见 `cloud-npcap.md`）。
- CE/CX/NE（SVRP）关机卡死崩溃：VirtualBox 7.x virtio-net 对未连接（null）网卡的发送死循环，与垫片无关；
  安装器第 7 步把这类网卡改挂空 intnet（`ensp-unused-*`）规避。
- VBoxSVC 每用户一个，权限由第一个拉起它的客户端决定。普通权限的 VBoxSVC 在跑时，CE/NE 启动超时
  （日志写不进 Program Files）。**在本机跑 VBoxManage 实验后要等 VBoxSVC 退出再让用户开 eNSP。**

## 文件与编码约定

- `.bat`：CRLF（`.gitattributes` 强制）。`.ps1` 含中文的保持 **UTF-8 带 BOM**（Windows PowerShell 5.1 依赖 BOM）。
- 安装器脚本面向中文用户，输出与注释用中文；C++/ASM 注释沿用英文。
- 在 bash 里拼含反斜杠的 Windows 路径容易被转义吃掉；改这类文件用编辑工具，不要用 sed/heredoc。

## 提交

- 前缀：`fix(shim)` / `fix(installer)` / `build` / `repo` / `docs` / `tools/dev` 等；正文写清原因与验证方法。
- 只在用户要求时提交 / 推送。上游有更新时 `git fetch upstream` 后合并到 `main`。
