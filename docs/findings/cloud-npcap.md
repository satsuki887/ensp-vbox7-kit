# Cloud 设备不认 Npcap（兼容模式下只剩 UDP）

**状态：原因已定位，未修复**；当前用"WinPcap 4.1.3 + 非兼容模式 Npcap"规避 · 记录于 2026-10-11

## 现象

卸载 WinPcap、改装 Npcap 1.89 并勾选 "WinPcap API-compatible Mode" 后：

- eNSP 的接口抓包（Wireshark）**正常**
- Cloud 设备的端口绑定里**只有 UDP**，看不到任何本机网卡

装回 WinPcap 4.1.3、Npcap 改为非兼容模式后，两者都正常。上游诊断脚本也记录了
"eNSP 的抓包只认 WinPcap；Npcap 的兼容层不被接受"，但没有说明原因。

## 原因

Cloud 由 `tools\eNSP_Cloud_Plugin.dll`（32 位）实现，直接用 `packet.dll` 的底层接口
（`PacketGetAdapterNames`、`PacketGetVersion`、`PacketOpenAdapter`、`PacketSendPacket` …），
并用 `iphlpapi!GetAdaptersAddresses` 和系统网卡逐一对照。

网卡枚举函数里是 WinPcap 官方示例的老写法（地址为 eNSP V100R003C00SPC100 自带的这份 DLL）：

```
1001151E  call PacketGetVersion
1001152B  movsx esi, byte ptr [eax]     ; esi = version[0]
1001152E  sub   esi, '0'                ; 主版本号
10011535  call  GetVersion
1001153B  ...Win9x 判断...
1001154A  cmp   esi, 4
1001154D  je    100115FA                ; 主版本 == 4 -> 按 ANSI 解析
10011553  ...否则按 WCHAR(UTF-16) 解析   ; WinPcap 3.x 在 NT 上返回宽字符列表
```

[`tools/dev/pcapprobe`](../../tools/dev/pcapprobe/run.bat) 实测两边的返回值：

| | WinPcap 4.1.3 | Npcap 1.89（兼容模式） |
|---|---|---|
| `PacketGetVersion()` | `"4.1.0.2980"` | **`"1.89"`** |
| `PacketGetAdapterNames` 格式 | ANSI，`名字…\0\0描述…\0\0` | 同样是 ANSI |
| 第一项 | `\Device\NPF_{GUID}` | `\Device\NPF_Loopback`（无 GUID） |

主版本被算成 `1`，插件以为是老 WinPcap，把 ANSI 列表当 UTF-16 解析，得到的全是乱码，
一个都对不上系统网卡，于是只剩 UDP。抓包走的是另一条路径，所以不受影响。

插件里另外两处 `PacketGetAdapterNames` 调用（`1000DEEC`、`10011631`）都是按字节解析，
没有版本分支。

## 修复思路（后续，需真机验证）

最小改动：`1001154D` 处的 `0F 84`（je）改为 `90 E9`（nop + jmp），目标不变，
让插件**始终走 ANSI 分支**。WinPcap 4.x 本来就走这条分支，所以对 WinPcap 用户无影响。
做成和 `patch_var_plugin.py` 一样的补丁器：校验出厂哈希、逐字节校验原值、可 `--restore`。

上线前还要确认：

1. `\Device\NPF_Loopback` 这一项在 ANSI 分支里会被安全跳过（对不上任何 GUID）。
2. Cloud 的实际收发包（`PacketOpenAdapter` / `PacketSendPacket` / `PacketReceivePacket`）
   在 Npcap 兼容层下正常：Cloud 桥接到本机网卡后双向 ping、抓包对照。
3. `eNSP_Client.exe` 和几种宿主侧设备进程（`eNSP_Router` / `eNSP_Switch` / `eNSP_Firewall`）
   也导入了 `PacketGetVersion`，需逐个确认是否有同样的版本分支。
4. 替换 `packet.dll` 返回值（代理 DLL）是另一条路，改动面更大，暂不考虑。
