# NOTICE —— 署名与第三方声明

## 本项目的来源

**ensp-vbox7-kit** 派生自 **[ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim)**，
原作者 **LBXaaa**，以 Mozilla Public License 2.0 发布。

- 本仓库完整保留了原项目截至提交 `d5cf369`（2026-10-07）的全部提交历史，每一处原始代码的作者
  都可以用 `git log` / `git blame` 追溯。
- COM 垫片的整体设计、IVirtualBox / IMachine 代理、版本伪装、`VAR_Plugin.dll` 补丁、
  安装 / 诊断 / 修复脚本，以及 `analysis/`、`docs/` 下的大部分逆向分析成果，均出自原作者。
- 原项目 README 原文存档于 [`docs/upstream/README.md`](docs/upstream/README.md)。
- 原作者的介绍文章：<https://developer.aliyun.com/article/1739948>

本仓库在其基础上所做的修改见 [`CHANGELOG.md`](CHANGELOG.md)。

## 许可证

- 原项目的文件，以及由这些文件修改而来的文件：**MPL-2.0**，版权归原作者及各自的贡献者。
- 本仓库新增的文件：同样采用 **MPL-2.0**。
- 许可证全文见 [`LICENSE`](LICENSE)。依 MPL-2.0 第 3.1、3.4 条，再分发本项目时须以 MPL-2.0
  提供源代码，且不得删除或修改其中的版权与许可声明。

## 第三方软件与商标

本项目只与下列软件**互操作**，与它们的权利人**没有任何隶属、合作或认可关系**。所列名称均为各自权利人的
商标或注册商标。

| 软件 | 权利人 | 本仓库的处理 |
|---|---|---|
| eNSP（含 `VAR_Plugin.dll`、`NGFW_Plugin.dll`、`eNSP_Cloud_Plugin.dll` 等） | 华为技术有限公司 | **不分发**。`VAR_Plugin.dll` 由 `tools/prepare-payload.ps1` 用使用者本机的副本就地生成 |
| Oracle VM VirtualBox | Oracle Corporation | **不分发**。基础包以 GPLv3 发布，请从官网获取 |
| WinPcap | Riverbed Technology（原 CACE Technologies） | **不分发** |
| Npcap | Nmap Software LLC | **不分发**。其许可证禁止未经授权的再分发 |
| Microsoft Visual C++ 运行时（`installer/payload/msvcrt-x86/VCRUNTIME140.dll`、`MSVCP140.dll`，x86，14.50.35719） | Microsoft Corporation | **随附**（沿袭原项目）。属于 Visual Studio 许可条款中允许随应用程序再分发的 Visual C++ 可再发行组件，文件带有效的 Microsoft 签名；版权归 Microsoft，不适用本项目的 MPL-2.0 |
| Windows SDK（NuGet 包，仅编译时用） | Microsoft Corporation | **不分发**，放在 `local/toolchain/` |

## 逆向分析材料

`analysis/`、`tools/disasm_output.txt` 等目录中有少量对 eNSP 与 VirtualBox 二进制的反汇编片段、字符串
摘录和运行日志；`docs/findings/` 中引用了个别指令地址。这些材料仅用于说明并实现与 VirtualBox 7.x 的互操作，
不包含可独立运行的第三方程序代码。
