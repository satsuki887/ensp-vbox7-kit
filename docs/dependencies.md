# 依赖与安装包

本仓库**不分发**下列任何一项。请从官方渠道获取，放进 `local/`（见 [`local/README.md`](../local/README.md)），
再用下表的 SHA-256 核对。表中哈希是本项目实际验证过的那一份。

## 运行环境

| 组件 | 版本 | 官方来源 | SHA-256 | 签名 |
|---|---|---|---|---|
| VirtualBox | **7.2.16** r174877 | `https://download.virtualbox.org/virtualbox/7.2.16/` | `9383a42bffa5c0ac4bc5f1c7d820478d84380d3a17b65aa9b43e6778cbdb615a` | Oracle America, Inc. |
| VirtualBox（仅回滚用） | 5.2.44 r139111 | `https://download.virtualbox.org/virtualbox/5.2.44/` | `2335e98f1c41f3aad5e16d2d5d18298e19d1cb04021fd752e3e2cd952996c7cd` | Oracle Corporation |
| WinPcap | 4.1.3 | `https://www.winpcap.org/install/`（已停更） | `fc4623b113a1f603c0d9ad5f83130bd6de1c62b973be9892305132389c8588de` | Riverbed Technology |
| Npcap | 1.89 | `https://npcap.com/#download` | `8aed85e900d783d1308506e919587d3e540451947af8a82f2d04f819e44305cc` | Nmap Software LLC |
| eNSP | V100R003C00SPC100（1.3.00.100） | 华为企业业务网站（已停止更新） | 安装包 zip：`69e4e1dfe5a6a6cfd2515047a33953203333c23e63b9cfe4d27af25aab2b6f52` | — |
| Python | 3.x | `https://www.python.org/` | — | — |

VirtualBox 两个官方哈希可与同目录下的 `SHA256SUMS` 对照；`安装.bat` 在安装包里缺 `VAR_Plugin.dll`
时会调用 Python 生成它。

**抓包驱动的装法（重要）**：推荐保留 WinPcap 4.1.3；Npcap 安装时**不要勾选** "WinPcap API-compatible Mode"。
不打补丁时，Npcap 兼容模式下 Cloud 设备只剩 UDP；只想用 Npcap 的话，先以管理员运行
`python patches\patch_pcap_version.py`（原因与验证见 [`findings/cloud-npcap.md`](findings/cloud-npcap.md)）。
先装 Npcap 兼容模式再装 WinPcap 会被拒绝（"已有更新版本"），要恢复时顺序是：卸载 Npcap → 装 WinPcap →
重装 Npcap（不勾兼容模式）。

## 编译 `VBox52.dll`（仅开发需要）

| 组件 | 说明 |
|---|---|
| Visual Studio 2022 Build Tools（或任意带 "x86/x64 C++ 工具" 的 VS） | `tools/dev/vsenv.bat` 用 `vswhere` 自动查找；可设 `VCVARS` 环境变量指定 |
| Windows SDK | 装了就直接用；没装时用下面两个 NuGet 包 |
| `Microsoft.Windows.SDK.CPP` 10.0.26100.9169 | `https://www.nuget.org/packages/Microsoft.Windows.SDK.CPP/10.0.26100.9169`，SHA-256 `475269434dcd808a67853773272f972c3229c0e10c3ddc821290e70cc0f6904d` |
| `Microsoft.Windows.SDK.CPP.x86` 10.0.26100.9169 | `https://www.nuget.org/packages/Microsoft.Windows.SDK.CPP.x86/10.0.26100.9169`，SHA-256 `2fd9e9d0c264254fe80d16b438083d968f82fa7d2f326cd0eca1ed8383601cf6` |

把两个 `.nupkg` 放进 `local/toolchain/`（文件名分别为 `microsoft.windows.sdk.cpp.nupkg`、
`microsoft.windows.sdk.cpp.x86.nupkg`），首次编译时会自动解压到 `local/toolchain/sdk/`。

用 VS 2022 Build Tools 14.44 + 上述 SDK 编译，`build\build.bat` 的输出为
`fc9797c39cdc3fa5048280c1c05befad3ac553888e87b1410c65596347a7a8dc`，与仓库中的 `VBox52.dll` 一致。
换别的编译器版本，字节会不同，但同一套工具链两次编译结果相同（`/Brepro`）。
