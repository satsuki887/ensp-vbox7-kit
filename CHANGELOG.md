# 更新记录

基线：上游 [LBXaaa/ensp-vbox-shim](https://github.com/LBXaaa/ensp-vbox-shim) `d5cf369`（2026-10-07）。
以下是本仓库在此之后的改动。每一项都在真机上验证过（Windows 11 build 26300、i9-13900HX、
eNSP 1.3.00.100、VirtualBox 7.2.16），验证方法写在对应的提交说明里。

## 0.1.0 —— 2026-10-11

### 修复（垫片 `VBox52.dll`）

- **`CreateProcessW` hook 的并发问题**。旧实现每次调用都"撤 hook → 调原函数 → 装回 hook"：两个线程同时
  启动 `VBoxManage`（eNSP 一次启动多台设备）时，有的调用会绕过 hook（USG 等设备漏掉 `--uart2` 注入），
  有的会执行到写了一半的跳转指令而崩溃。16 线程测试中旧版漏注入 229/400 次或直接崩溃；**2 个线程就足以崩溃**。
- **hook 安装的竞争**。用普通 `bool` 防重入，两个线程同时安装时，第二个会把第一个写入的 jmp 当成
  "原始字节"保存，之后撤 hook 时无限递归。改为原子状态机。
- **兼容模式下 hook 装不上**。eNSP 常被设为"Windows 7 兼容 + 以管理员身份运行"，兼容层会让
  `GetProcAddress` 返回包装函数。新实现自己解析导出表，用微软热补丁格式挂在
  `kernelbase!CreateProcessW` 上（一次 16 位原子写入），备选方案为原子替换 `kernel32` 跳板的导入槽。
- **日志栈缓冲区溢出**。`DBG` 用 `sprintf` 写 512 字节栈缓冲区，编译又是 `/GS-`；hook 会把整条命令行写进
  日志。实测旧版写出过 1207 字节的一条日志。改为 `snprintf`，超长截断。
- `CreateProcessW` 返回后保留 `GetLastError`；`CoGetClassObject` 的导入表写入改为原子操作。

### 修复（安装器）

- `CLSID_VirtualBox` 只写 32 位视图。原版 7.2.16 的 64 位视图只有 `LocalServer32`；旧安装器塞进去一个指向
  32 位 DLL 的 `InprocServer32`，导致 64 位程序以 `CLSCTX_ALL` 创建 VirtualBox 对象时报 `0x800700C1`。
  升级安装会清掉旧版留下的那一项。
- 升级安装不再把旧版垫片当成"原文件"备份成 `.orig.bak`（否则卸载时会被"还原"回去）；卸载能识别历次版本。

### 仓库与构建

- 不再提交华为的 `VAR_Plugin.dll`：`tools/prepare-payload.ps1` 从使用者本机的 eNSP 生成，
  `安装.bat` 在缺少时自动调用。生成结果与上游随附的那份逐字节一致。
- `build.bat` 用 `vswhere` 自动查找 Visual Studio；没装 Windows SDK 时使用 `local/toolchain` 中的官方
  NuGet 包。`/Brepro` 可复现编译，同一工具链两次编译结果逐字节相同。
- 新增 `tools/dev/`：hook 并发测试、VirtualBox 虚表探针、`packet.dll` 探针、minidump 解析器、
  安装器沙箱测试。
- 新增 `local/`（git 忽略）存放安装包、备份与崩溃现场；`.gitattributes` 固定 `.bat` 为 CRLF。

### 新发现（未修复，见 `docs/findings/`）

- IVirtualBox 方法区槽位整体少算 12（类型库与运行时双重确认）：`vtable-reserved-slots.md`
- Cloud 设备不认 Npcap 兼容模式的根因：`cloud-npcap.md`
- CE/NE 关机时 `VBoxDD.DLL` 中 NAT 线程崩溃，以及旧实例未退出时重开导致插件卡死：`svrp-shutdown-crash.md`
- 起点：VirtualBox 5.2.44 的 `VMMR0.r0` 导致 0xD1 蓝屏：`bsod-vbox52.md`
