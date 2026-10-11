# local/ —— 只放本机、不进 git 的东西

这个目录除了本说明以外全部被 `.gitignore` 排除。放在这里的东西要么不能再分发，
要么只对这台机器有意义。换电脑或重装时，从这里取用。

| 目录 | 内容 | 为什么不进 git |
|---|---|---|
| `installers/virtualbox/` | VirtualBox 7.2.16（在用）与 5.2.44（回滚用）官方安装包 | 体积大；直接从 Oracle 官网下载即可 |
| `installers/pcap/` | WinPcap 4.1.3、Npcap 1.89 安装包 | **Npcap 许可证禁止未授权再分发**；WinPcap 也已停更，留个原件 |
| `installers/ensp/` | eNSP V100R003C00SPC100 安装包 | 华为软件，不得再分发 |
| `toolchain/` | Windows SDK 的 NuGet 包（编译 `VBox52.dll` 用，免安装 SDK） | 体积大；微软官方 NuGet 可下 |
| `backups/` | 换 VirtualBox 前后的注册表 / `.vbox` 配置备份 | 本机专属 |
| `crash-dumps/` | 蓝屏转储与崩溃现场 | 本机专属，可能含隐私 |

各安装包的官方来源与 SHA-256 见 [`docs/dependencies.md`](../docs/dependencies.md)，
拿到文件后可以自行核对。
