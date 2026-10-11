# IVirtualBox 方法区少算了 12 个保留槽位

**状态：已确认，未修复**（实际可用，属"碰巧能用"）· 记录于 2026-10-11 · VirtualBox 7.2.16

上游在 [`docs/vtable-mapping.md`](../vtable-mapping.md) 里已经把这一点列为"尚未解决的矛盾"：
方法区的槽位表"整体偏低 12"，但 `VAR_Plugin` 补丁用的正是这张表，而 AR 设备实测可用。
本文给出运行时证据，结论是：**表确实错了**。

## 证据

### 1. 类型库

[`tools/dev/vboxprobe/run.bat`](../../tools/dev/vboxprobe/run.bat) 在 32 位 PowerShell 中读取
32 位客户端（eNSP）实际使用的类型库 `x86\VBoxProxyStub-x86.dll`：

```
IVirtualBox   7   get_Version
...
IVirtualBox  35   get_CloudProviderManager
IVirtualBox  36   get_InternalAndReservedAttribute1IVirtualBox
...
IVirtualBox  47   get_InternalAndReservedAttribute12IVirtualBox
IVirtualBox  48   ComposeMachineFilename
IVirtualBox  51   OpenMachine
IVirtualBox  52   RegisterMachine
IVirtualBox  53   FindMachine
IVirtualBox  66   GetExtraData
...
IVirtualBox  91   InternalAndReservedMethod6IVirtualBox
```

自身 85 个方法 + 继承 7 个 = **92**，与注册表 `Interface\{2CE10519-…}\NumMethods` 一致；
接口 IID 与垫片里写死的 `IID_VBox7_IVirtualBox` 相同，所以 7.2.8 与 7.2.16 布局一致。

### 2. 运行时

同一工具里的 `probe.exe`（32 位，连真实 VBoxSVC，只读）：

| 调用 | 结果 |
|---|---|
| `[7]` get_Version | `S_OK`，`7.2.16` |
| `[41]` 按 1 参数 getter 调用（代码里当作 `findMachine`） | **`E_NOTIMPL`** —— 是保留属性 |
| `[53]` FindMachine("AR_Base") | `S_OK`，返回的机器名 `AR_Base` |

垫片自己的延迟注册（`try_register_pair(…, 51, 52)`）早已用对了槽位，源码注释里也记了误用
`[39]` 时的崩溃现场。

## 影响范围

| 位置 | 用的槽位 | 正确槽位 | 实际是否被调用 |
|---|---|---|---|
| `src/vbox52_thunks.asm` 方法区 `UNI_THUNK_DIAG thunk_25..49` | 36–70 | 48–82 | 上游分析：eNSP_VBoxServer 只调代理 `[1]`、`[3]–[6]` |
| `src/vbox52_proxy.cpp` `wrap_findMachine/openMachine/registerMachine` | 41 / 39 / 40 | 53 / 51 / 52 | 同上，未见调用 |
| `patches/patch_var_plugin.py` 全部 29 处 | 例：findMachine→41、getExtraData→54、openMedium→47 | 53、66、59 | **AR 插件直接持有真实 7.2 对象**，是否调到取决于 AR 启动路径 |
| `g_imachine_map[i] = i + 4`（IMachine） | 统一 +4 | 需逐槽 | 上游：未被调用 |

参数个数相同的误调用（如 getExtraData → `[54]` GetMachinesByGroups，都是 2 个参数）只会返回错误；
参数个数不同的（如 findMachine → `[41]` 1 参数 getter）还会把调用者的参数当输出指针写 4 字节，
并让栈不平衡 4 字节。AR 目前能用，最可能是因为它的启动路径没走到参数个数不同的那几处，或能容忍失败。

## 修复思路（后续）

1. 用 `tools/dev/vboxprobe/out/tlb.tsv` 生成方法区映射表，替换手写表（属性区 7–35 现已正确）。
2. 生成第二版 `VAR_Plugin` 补丁表；旧补丁与新补丁可 A/B 切换（只换这一个文件）。
3. 在 AR 启动、保存、导入导出配置等路径上逐一验证，再决定是否默认启用新补丁。
4. `IMachine` 同理改为按类型库逐槽映射（7.2.16 的 `IMachine` NumMethods = 229）。

**注意**：修正后插件会"真正找到机器"，可能走上从未测过的新分支。必须在真机上完整回归后再发布。
