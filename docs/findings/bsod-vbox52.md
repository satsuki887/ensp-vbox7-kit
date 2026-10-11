# 蓝屏 0xD1：VirtualBox 5.2.44 的 VMMR0.r0（已解决）

**状态：已解决**（换成 VirtualBox 7.2.16 + 本仓库垫片）· 记录于 2026-10-11

## 现象

用 eNSP（基于 VirtualBox 设备）练习时，两次整机蓝屏，只能强制关机：

| 时间 | BugCheck | 参数 1（访问地址） | 参数 4（出错指令） |
|---|---|---|---|
| 2026-10-08 23:03 | `0xD1` DRIVER_IRQL_NOT_LESS_OR_EQUAL | `0xB1FB45C` | `0xFFFFF80073E86B10` |
| 2026-10-11 08:25 | `0xD1` | `0x83A0000` | `0xFFFFF80565583B13` |

IRQL = 2、读操作、地址都是低位用户态地址 —— 典型的"内核驱动在 DISPATCH_LEVEL 解引用了无效指针"。

## 定位

两份 minidump 用 [`tools/dev/minidump/parse_minidump.py`](../../tools/dev/minidump/parse_minidump.py)
（解析 triage dump 的驱动列表与栈上地址，不依赖 WinDbg）解出来：

- 出错指令分别落在 **`VMMR0.r0+0xA6B10`** 与 **`VMMR0.r0+0xB3B13`**
- 栈上从下到上是 `ntoskrnl → VBoxDrv.sys → 一长串 VMMR0.r0`

`VMMR0.r0` 是 VirtualBox 的 ring-0 虚拟机监视器，经 `VBoxDrv.sys` 的 ioctl 进入。
网络过滤驱动（`VBoxNetLwf`、`npf`、`vmnetbridge`）都不在栈上，排除。

## 原因判断

VirtualBox 5.2.44（2020 年）早于这台机器的两样东西：

- **i9-13900HX 的 P/E 混合架构**
- **Windows 11 build 26300** 的内核

同时排除了 Hyper-V / VBS / 内存完整性冲突：`HypervisorPresent = False`，VBS 状态 0，
虚拟机平台与 WHP 均未启用。

## 处置

卸载 5.2.44 → 装 7.2.16（Oracle 签名，`VMMR0.r0` 版本 7.2.16.174877）→ 用本仓库垫片让
eNSP 跑在 7.2 上。之后多轮同时启动 5 台设备（含 VMware 并开）未再蓝屏。

## 复现材料

`local/crash-dumps/100826-16593-01.dmp`、`101126-15203-01.dmp`（本机，不进 git）。
