# CE / NE 等 SVRP 设备关机时 VBoxHeadless 崩溃

**状态：根因已定位（VirtualBox 7.x virtio-net 对"未连接"网卡的 bug），安装器第 7 步规避；
已在 CE 的克隆上 A/B 验证，待 eNSP 内回归** · 记录于 2026-10-11 · VirtualBox 7.2.16

与垫片无关：崩溃的是 VirtualBox 自己的 64 位 `VBoxHeadless.exe`，32 位的 `VBox52.dll` 不会加载进这个进程。

## 现象

停止 CE6800 / NE9000（或直接关闭 eNSP）后，**不需要做任何其他操作**，约 3 分钟后弹出：

> VBoxHeadless.exe - 应用程序错误：0x00007FFB…6F5A 指令引用了 0x0000000000000024 内存。该内存不能为 read。

不点"确定"，这个进程会一直占着内存（每台 1–4 GB）。NE40E 那次是正常退出的，没有崩溃。

上游 `installer/cleanup_orphans.ps1` 头部记录的是同一个现象（"0x…24 该内存不能为 read"）。

## 证据（`local/crash-dumps/svrp-shutdown-2026-10-11/`）

两台设备的 `VBox.log` 时间线完全一致：

| 阶段 | CE（第三次） | NE9000 |
|---|---|---|
| eNSP 发 power off → `RUNNING → POWERING_OFF` | 02:28 | 10:09 |
| `PDMR3ThreadSuspend -> VERR_TIMEOUT for 'legacy-xmitq<0>'` | +60.0 s | +60.0 s |
| `POWERING_OFF → OFF → DESTROYING` | 03:28 | 11:09 |
| `NAT: RTWinPoll returned error=10038` → 未处理异常 | +120 s，05:28 | +120 s，13:09 |
| 崩溃位置 | `VBoxDD.DLL+0x216f5a`，读 `0x24` | `VBoxDD.DLL+0x21713b`，读 `0x1818` |

CE 两次崩溃（10:04:58、10:21:55）偏移完全相同 —— 确定性的同一条指令。

## 根因

所有 SVRP 虚拟机（`CE` `CX` `NE40E` `NE5000E` `NE9000`，配置是 eNSP 自带的 `*.xml`）都是：

```
nic1="null"  nictype1="virtio"      ; 未连接
nic2="nat"   nictype2="virtio"      ; eNSP 经端口转发连管理口
```

`VBox.log` 的 CFGM 树里 `/Devices/virtio-net/0/LUN#0/` 下**没有驱动**，即设备侧 `pDrv == NULL`。

VirtualBox 7.x 重写过的 virtio-net（`src/VBox/Devices/Network/DevVirtioNet.cpp`）里，
`virtioNetR3TransmitPkts` 的发送循环是：

```c
while (virtioCoreR3VirtqAvailBufPeek(...) == VINF_SUCCESS)   // 只 peek，不取走
{
    ...
    if (pThisCC->pDrv)
    {
        ... 发送 ...
        virtioCoreR3VirtqAvailBufNext(...);                  // 只有这里才消费描述符
        virtioCoreR3VirtqUsedBufPut(...);
    }
    ...
}
```

没挂驱动时描述符永远不被消费，循环一直 peek 到同一个描述符。客机往这块卡发出第一个包后，
它的 TX 线程（`legacy-xmitq<0>`，名字里的 `<0>` 是队列对编号，不是网卡编号）就在用户态死循环，
power off 时不响应挂起请求 → 60 s 超时 → 销毁阶段 NAT 再卡 120 s → 访问违例。
NE40E 偶尔不崩，最可能是那次客机没往 eth0 发过包。

（5.2 时代是旧的 legacy-only virtio-net 实现，未连接的网卡会直接丢包，所以华为的配置那时没问题。）

## 验证（2026-10-11，纯 VirtualBox，不经 eNSP）

用 `VBoxManage clonevm CE` 做了一台克隆，在它上面 A/B：

| | nic1 = null（原样） | nic1 = 空 intnet |
|---|---|---|
| 运行中 | 开机约 25 s 后**一个线程持续占满 1 核**（用户态 144 s / 内核态 0.3 s，不是 vCPU） | CPU ≈ 0 |
| power off | `VERR_TIMEOUT for 'legacy-xmitq<0>'`，+120 s 崩在 `VBoxDD.DLL+0x216f5a`（与 eNSP 下相同） | **0.26 s**，`DESTROYING → TERMINATED`，状态 `poweroff` |

VirtualBox 7.2.18 / 7.2.20 的 changelog 里没有相关修复（只有 NAT 端口转发、CPU 占用等），升级不能指望。

## 修法：安装器第 7 步

`installer/install.ps1` 的 `Set-UnattachedVirtioNics`：对配置文件在 eNSP 目录下的 VM，
把每块 `null + virtio` 的网卡改挂到只有它自己的内部网络 `ensp-unused-<VM>-nic<N>`。
客机看到的网卡型号、MAC、链路状态都不变，发出的帧被 intnet 接走丢弃。

- 只改 `null + virtio`，其它网卡（包括 `null + e1000`）不动；VM 不在 `poweroff`/`aborted` 状态时跳过并提示。
- 卸载时按 `ensp-unused-` 前缀认出来，改回 `null`。
- 必须在提权侧跑：这些 `.xml` 在 Program Files 里，而 eNSP（RUNASADMIN）用的也是提权的 VBoxSVC。
- 测试：`tools/dev/installer-tests/test_svrp_nic.ps1`（建一台临时空 VM，验证安装/卸载两个方向）。

**还没做的**：在 eNSP 里完整跑一遍 CE / NE 的启动、配置、保存、关机。

## 附带问题：旧实例未退出时重开同型设备，插件会卡死

SVRP 设备不是链接克隆，每种只有一台固定的虚拟机（`CE`、`NE9000`…）。在旧实例还处于上表的 3 分钟里重开：

1. 插件的 `startvm CE` 因虚拟机被占用而失败；
2. 插件随后连上的是**旧实例**仍在监听的管理口，误以为设备已起来；
3. 旧实例崩溃后连接断开，插件进入每 2 秒重连一次的循环，界面一直 `###`，
   在 eNSP 里停止 / 重新启动也不会再发 `startvm`。

关机变快之后这个窗口随之消失。未打修复时的规避：关闭 eNSP → `installer\清理残留.bat` → 重开 eNSP。

## 后续

1. 整理成纯 VirtualBox 复现（任意带 virtio 网卡、`--nic1 null` 的 Linux 客机，往 eth0 发一个包后 power off），向 Oracle 提 bug。
2. eNSP 重装会带回原版 `*.xml`，需要重跑安装器（或单独跑第 7 步）。
