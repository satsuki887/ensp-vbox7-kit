# registry/

把 eNSP 接到垫片上的 Windows 注册表改动。它们在一台全新机器上，复现垫片安装
所做的两处注册表层面的改动。所有值都已对照一份活的、能正常工作的安装核验过。

导入顺序有讲究：**先版本伪装，再 CLSID 劫持**。

```bat
reg import 01_version_spoof.reg
reg import 02_clsid_inprocserver.reg
```

（或者双击每个 .reg。需要管理员权限——它们写的是 HKLM。）

## 每个文件做什么

| 文件 | 作用 |
|------|------|
| `01_version_spoof.reg`      | 在 64 位和 32 位两个视图里，把 `Oracle\VirtualBox` 的 `Version` 与 `VersionExt` **都**设为 5.2.44，好让 eNSP 的 5.2.x 版本闸门放行（机器实际跑的是 7.2.x）。两个值必须逐字相同、不带构建号：eNSP 读 `VersionExt` 时复用了 `InstallDir` 的缓冲区长度，`VersionExt` 一旦比 `InstallDir` 长，读取即失败 |
| `02_clsid_inprocserver.reg` | **只在 32 位视图**（`WOW6432Node`）里为 `CLSID_VirtualBox` `{B1A7A4F2-…}` 写一个指向 `…\Huawei\eNSP\tools\VBox52.dll` 的 InprocServer32，这样 eNSP 的 32 位 `CoCreateInstance` 加载的是垫片。64 位视图不动：往那里写指向 32 位 DLL 的项会让 64 位程序报 `0x800700C1`（旧版安装器犯过这个错） |

卸载没有对应的静态 `.reg`：要把版本字符串还原成**本机** VirtualBox 的真实版本，而这个值只能现场读，写不进静态文件。用 `卸载.bat`（现场跑 `VBoxManage --version` 取值后回填）。

## 路径

这些 .reg 文件用的是标准安装位置：

- eNSP：`C:\Program Files\Huawei\eNSP\tools\VBox52.dll`
- VirtualBox：`C:\Program Files\Oracle\VirtualBox\`

如果你的安装在别处，导入前先改路径。

## 前提

- 已装好 VirtualBox **7.2.x**（二进制必须真的是 7.2；只有注册表在假装 5.2）。
- `VBox52.dll` 已编译并拷到 `…\eNSP\tools\`（见 `build/`）。

## 卸载

1. 把版本字符串放回真实的 7.2.x。用 `卸载.bat`——它现场执行
   `VBoxManage --version` 取值后回填 `Version` 与 `VersionExt`（两个视图、两个值都取行首的
   `主.次.修订`，不带 `r` 构建号）。手工等价操作：读出该值后自己写回
   `HKEY_LOCAL_MACHINE\SOFTWARE\Oracle\VirtualBox` 与 `…\WOW6432Node\…`。
2. 删掉 32 位视图里的 CLSID 项。实测原版 VirtualBox 7.2.16 的 32 位视图里**根本没有**这个键，
   对 VirtualBox 跑「修复」也不会删它，所以要手动删（管理员命令提示符）：

   ```bat
   reg delete "HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{B1A7A4F2-47B9-4A1E-82B2-07CCD5323C3F}" /f
   ```

   安装前若用 `reg export` 备份过这个键，导入备份即可。`卸载.bat` 故意不替你删：这个键的原始状态
   随 VirtualBox 版本而异，猜错了可能破坏 VirtualBox 的 COM 注册。

## 为什么版本伪装要写两个视图（而 CLSID 只写 32 位视图）

eNSP 是 32 位进程，但读版本号时它用 `KEY_QUERY_VALUE | KEY_WOW64_64KEY`（掩码 `0x101`）打开这个键，
**读的是 64 位视图**（语料 30 个模块里 22 处打开点，掩码无一例外）。32 位视图也写一份，
供读它的工具使用——eNSP 自己不看那里。

CLSID 则相反：eNSP 的 `CoCreateInstance` 是普通的 32 位 COM 激活，只看 32 位视图。64 位视图归
VirtualBox 自己的 64 位客户端使用，往那里塞指向 32 位 DLL 的 InprocServer32 只会弄坏它们。
