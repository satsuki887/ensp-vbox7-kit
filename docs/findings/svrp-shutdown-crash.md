# CE / NE 等 SVRP 设备关机时 VBoxHeadless 崩溃

**状态：可稳定复现，原因已定位到 VirtualBox 7.2 的 NAT 网卡，未修复** · 记录于 2026-10-11 · VirtualBox 7.2.16

与垫片无关：崩溃的是 VirtualBox 自己的 64 位 `VBoxHeadless.exe`，32 位的 `VBox52.dll` 不会加载进这个进程。

## 现象

停止 CE6800 / NE9000（或直接关闭 eNSP）后，**不需要做任何其他操作**，约 3 分钟后弹出：

> VBoxHeadless.exe - 应用程序错误：0x00007FFB…6F5A 指令引用了 0x0000000000000024 内存。该内存不能为 read。

不点"确定"，这个进程会一直占着内存（每台 1–4 GB）。NE40E 这次是正常退出的，没有崩溃。

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

- CE 两次崩溃（10:04:58、10:21:55）偏移完全相同 —— 确定性的同一条指令。
- `legacy-xmitq<0>` 是 0 号网卡的发包队列线程。SVRP 设备的 0 号网卡挂 NAT，eNSP 通过 NAT 端口转发连
  `127.0.0.1` 的管理口（插件日志里的 `ConnectToHost`）。
- `10038` = `WSAENOTSOCK`：销毁流程已经关掉了 socket，NAT 线程仍在轮询，随后解引用已释放的状态。

## 附带问题：旧实例未退出时重开同型设备，插件会卡死

SVRP 设备不是链接克隆，每种只有一台固定的虚拟机（`CE`、`NE9000`…）。在旧实例还处于上表的 3 分钟里重开：

1. 插件的 `startvm CE` 因虚拟机被占用而失败；
2. 插件随后连上的是**旧实例**仍在监听的管理口，误以为设备已起来；
3. 旧实例崩溃后连接断开，插件进入每 2 秒重连一次的循环，界面一直 `###`，
   在 eNSP 里停止 / 重新启动也不会再发 `startvm`。

**规避**：关闭 eNSP → `installer\清理残留.bat` → 重开 eNSP。

## 后续可尝试

1. 换 0 号网卡型号（查 `CE.xml` / `.vbox` 里的 `adapter type`），观察 `legacy-xmitq` 是否还会超时。
2. 用 VirtualBox 7.2.18 / 7.2.20 复测，翻 changelog 里与 NAT / power off 相关的修复。
3. 让 eNSP 先发 ACPI 关机、超时再 power off（需要在 `CreateProcessW` hook 里改写 `controlvm … poweroff`），
   看能否绕开卡死的发包队列。
4. 若能稳定复现于纯 VirtualBox（不经 eNSP），整理日志向 Oracle 提 bug。
5. 让 `清理残留.bat` 识别"已 `OFF`/`DESTROYING` 但进程未退"的实例，eNSP 开着时也能安全清理。
