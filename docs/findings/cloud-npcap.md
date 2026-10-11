# Cloud 设备不认 Npcap（只剩 UDP）

**状态：已修复，补丁器 `patches/patch_pcap_version.py`**；2026-10-11 在 eNSP 内用 Npcap 1.89 验证：
Cloud 能列出并绑定本机网卡，抓包正常。WinPcap 4.1.3 下行为不变 · 记录于 2026-10-11

## 现象（修复前）

卸载 WinPcap、改装 Npcap 1.89 并勾选 "WinPcap API-compatible Mode" 后：

- eNSP 的接口抓包（Wireshark）**正常**
- Cloud 设备的端口绑定里**只有 UDP**，看不到任何本机网卡

上游诊断脚本也记录了"eNSP 的抓包只认 WinPcap；Npcap 的兼容层不被接受"，但没有说明原因。

## 原因：两道关

Cloud 由 `tools\eNSP_Cloud_Plugin.dll`（32 位）实现，直接用 `packet.dll` 的底层接口。网卡枚举函数
（RVA `0x11480`）是 WinPcap 官方示例的老写法。`eNSP_Client.exe` 里有逐字节相同的一份（`004D6180` 起），
两个模块都要改。

### 1. 版本号

```
1001151E  call PacketGetVersion
1001152B  movsx esi, byte ptr [eax]     ; esi = version[0]
1001152E  sub   esi, '0'                ; 主版本号，存到 [esp+1Ch]
...
1001154A  cmp   esi, 4
1001154D  je    100115FA                ; == 4 -> 按 ANSI 解析列表；否则按 UTF-16（WinPcap 3.x）
...
100113FC  cmp   dword ptr [esp+1Ch], 4  ; 逐个网卡检查里再判一次：
10011401  jne   10011439                ;   == 4 按 64 位读 NetType.LinkSpeed，否则按 32 位
```

Npcap 报 `"1.89"`，主版本被算成 1，两处都走了 WinPcap 3.x 的路径。

### 2. 链路速率过滤

逐个网卡检查（`100113E0`）要求 `PacketOpenAdapter` 成功、`LinkType == 0`（以太网）、
`LinkSpeed >= 10 Mbps`。逐个网卡重放这一流程（2026-10-11，本机）：

| | WinPcap 4.1.3 | Npcap 1.89 |
|---|---|---|
| `PacketGetVersion()` | `"4.1.0.2980"` | `"1.89"` |
| `PacketGetNetType` 的 `LinkSpeed` | 真实值（1 Gbps、100 Mbps、Wi-Fi Direct 1.5 Mbps…） | **全部为 0** |
| `\Device\NPF_Loopback` | 无此项 | `LinkType = 0xFFFFFFFF`，被类型检查挡掉 |

所以只修版本号还不够：每块网卡仍因速率为 0 被丢弃。插件里另一条打开网卡的路径（`1000DEEC`，
不看版本号）有同样的速率检查。

### 其它模块

所有导入 `PacketGetVersion` 的模块都查过：`eNSP_Router.exe`、两个 `eNSP_Switch.exe`、
`eNSP_Firewall.exe` 也有版本分支，但没有对应到任何可见症状（Npcap 下交换机等照常工作）。

## 修复：`patches/patch_pcap_version.py`

| 模块 | 位置 | 改动 |
|---|---|---|
| Cloud 插件 | `1001152B`（文件 `0x1152B`） | `movsx esi,[eax]; sub esi,'0'` → `mov esi,4; nop` |
| Cloud 插件 | `1001141E`（`0x1141E`），列表 | 速率检查改为只丢弃 `0 < LinkSpeed < 10 Mbps` |
| Cloud 插件 | `1000DF3F`（`0xDF3F`），打开网卡 | 同上 |
| eNSP_Client | `004D6225`（`0xD6225`） | 同 Cloud 的版本号 |
| eNSP_Client | `004D611E`（`0xD611E`） | 同 Cloud 的速率检查 |
| 设备进程（`--devices`） | 各一处 | 只改版本号 |

速率检查原来是 17 字节的 `cmp [esp+X+4],0; ja pass; cmp [esp+X],989680h; jb drop`，换成等长的
`nop×5; mov eax,[esp+X]; dec eax; cmp eax,98967Fh; jb drop`：速率 0 时 `dec` 得到 `0xFFFFFFFF`，
不小于阈值，放行；1 bps 到 10 Mbps 之间仍丢弃。跳转目标不变，`eax` 在两条出口上都会被重新赋值。

- WinPcap 4.x 下主版本本来就是 4、速率从不为 0，**行为不变**（枚举结果补丁前后逐项相同）。
- Npcap 下 Cloud 会多列出几项 WinPcap 下被速率挡掉的网卡（WAN Miniport、蓝牙 PAN、Wi-Fi Direct），无害。
- 补丁器的判断方法：把各补丁点恢复为出厂字节后，整个文件的哈希必须等于出厂哈希。所以出厂、全补、
  部分补（例如只打过旧版的版本号补丁）三种状态都能识别，其它文件一律拒绝。默认留 `.bak`，可 `--restore`。

## 验证

`tools\dev\pcapprobe\cloud.bat` 在 eNSP 之外直接调用插件自己的枚举函数，分别用系统的 packet.dll
和 Npcap 的 packet.dll 各跑一次（只用插件副本，不动 Program Files）。2026-10-11 本机结果：

| | 出厂插件 | 只修版本号 | 版本号 + 速率 |
|---|---|---|---|
| WinPcap | 6 块 | 6 块（相同） | 6 块（相同） |
| Npcap | 0 块 | **0 块** | **12 块**（含 Realtek、Intel Wi-Fi、Host-Only、VMnet1/8） |

eNSP 内验证不用卸载 WinPcap：`packet.dll` 不是 KnownDLL，程序目录比 System32 先被搜索。把
`C:\Windows\SysWOW64\Npcap\Packet.dll` 复制到 eNSP 根目录，eNSP 就改用 Npcap；删掉即还原
（复制要在**管理员**命令提示符里做，否则会静默失败）。2026-10-11：只修版本号时仍只有 UDP，
补上速率后 Cloud 能列出本机网卡，抓包正常。

## 切到 Npcap 的做法

1. 管理员运行 `python patches\patch_pcap_version.py`（关闭 eNSP 后）。
2. 卸载 WinPcap，Npcap 勾选 "WinPcap API-compatible Mode"；或保留 WinPcap，只按上面的方法给 eNSP 单独放一份 Npcap 的 `Packet.dll`。
