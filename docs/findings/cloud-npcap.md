# Cloud 设备不认 Npcap（兼容模式下只剩 UDP）

**状态：原因已定位，补丁器已就绪（`patches/patch_pcap_version.py`）**；2026-10-11 本机已给
Cloud 插件和 eNSP_Client 打上补丁，用户反馈 Cloud 与抓包正常。Npcap 下的 A/B 记录待补全；
当前仍用"WinPcap 4.1.3 + 非兼容模式 Npcap" · 记录于 2026-10-11

## 现象

卸载 WinPcap、改装 Npcap 1.89 并勾选 "WinPcap API-compatible Mode" 后：

- eNSP 的接口抓包（Wireshark）**正常**
- Cloud 设备的端口绑定里**只有 UDP**，看不到任何本机网卡

装回 WinPcap 4.1.3、Npcap 改为非兼容模式后，两者都正常。上游诊断脚本也记录了
"eNSP 的抓包只认 WinPcap；Npcap 的兼容层不被接受"，但没有说明原因。

## 原因

Cloud 由 `tools\eNSP_Cloud_Plugin.dll`（32 位）实现，直接用 `packet.dll` 的底层接口
（`PacketGetAdapterNames`、`PacketGetVersion`、`PacketOpenAdapter`、`PacketGetNetType` …）。
网卡枚举函数里是 WinPcap 官方示例的老写法（地址为 eNSP V100R003C00SPC100 自带的这份 DLL）：

```
1001151E  call PacketGetVersion
1001152B  movsx esi, byte ptr [eax]     ; esi = version[0]
1001152E  sub   esi, '0'                ; 主版本号
10011531  mov   [esp+1Ch], esi          ; 存起来，后面还要传给 100113E0
10011535  call  GetVersion
1001153B  ...Win9x 判断...
1001154A  cmp   esi, 4
1001154D  je    100115FA                ; 主版本 == 4 -> 按 ANSI 解析
10011553  ...否则按 WCHAR(UTF-16) 解析   ; WinPcap 3.x 在 NT 上返回宽字符列表
```

主版本号还会作为参数传给逐个网卡检查的 `100113E0`，那里有**第二个分支**：

```
100113FC  cmp  dword ptr [esp+1Ch], 4
10011401  jne  10011439
          ; == 4: NetType.LinkSpeed 按 64 位读（偏移 8），WinPcap 4 / Npcap 的结构
          ; != 4: LinkSpeed 按 32 位读（偏移 4），WinPcap 3.x 的结构
          ; 两边都要求 LinkSpeed >= 10 Mbps，否则丢弃该网卡
```

[`tools/dev/pcapprobe`](../../tools/dev/pcapprobe/run.bat) 实测两边的返回值：

| | WinPcap 4.1.3 | Npcap 1.89 |
|---|---|---|
| `PacketGetVersion()` | `"4.1.0.2980"` | **`"1.89"`** |
| `PacketGetAdapterNames` 格式 | ANSI，`名字…\0\0描述…\0\0` | 同样是 ANSI |
| 第一项 | `\Device\NPF_{GUID}` | `\Device\NPF_Loopback`（无 GUID） |

主版本被算成 `1`，插件以为是老 WinPcap：把 ANSI 列表当 UTF-16 解析，得到的全是乱码；
就算解析对了，`LinkSpeed` 也会从结构体的填充字节里读，网卡照样被丢弃。于是只剩 UDP。
抓包走的是另一条路径，所以不受影响。

插件里另一处枚举（`1000DEEC`）不看版本号，始终按 ANSI + 64 位 `LinkSpeed` 处理。

### 其它模块里的同一段代码

所有导入 `PacketGetVersion` 的模块都查过（dumpbin 反汇编）：

| 模块 | 版本号用法 |
|---|---|
| `eNSP_Client.exe` | **与 Cloud 插件逐字节相同的两处分支**（`004D6225` 起）。Cloud 配置界面的网卡列表很可能来自这里，必须一起补 |
| `vboxserver\devices\AR\AR\eNSP_Router.exe` | 主版本存进全局变量，两处 `cmp …, 4` |
| `vboxserver\devices\LSW\s3700\eNSP_Switch.exe`、`s5700\eNSP_Switch.exe` | 同上 |
| `vboxserver\devices\FW\USG5500\eNSP_Firewall.exe` | 直接比 `version[0] == '4'` |

设备进程里的分支目前没有对应到任何可见症状（Npcap 下交换机等照常工作）。

## 修复：`patches/patch_pcap_version.py`

不去逐个改分支，而是**在算主版本号的那一处直接写死 4**：

| 模块 | 文件偏移 | 原字节 | 补丁后 |
|---|---|---|---|
| Cloud 插件 | `0x1152B` | `0F BE 30 83 EE 30`（movsx esi,[eax]; sub esi,'0'） | `BE 04 00 00 00 90`（mov esi,4; nop） |
| eNSP_Client | `0xD6225` | 同上 | 同上 |
| Router / S3700 / S5700 | `0x7665A3` / `0x2D42BE3` / `0x310D033` | `0F BE 02 83 E8 30` | `B8 04 00 00 00 90`（mov eax,4; nop） |
| Firewall | `0x1B2DC7` | `74 02`（je） | `EB 02`（jmp） |

- 一处补丁覆盖该模块里所有用到版本号的分支。WinPcap 4.x 下主版本本来就是 4，**行为不变**。
- 原指令里没有绝对地址，所以不涉及重定位。
- 默认只补 Cloud 插件和 eNSP_Client；`--devices` 才连设备进程一起补。
- 和 `patch_var_plugin.py` 一样：校验出厂与补丁后的整文件 SHA-256，写前逐字节核对，默认留 `.bak`，可 `--restore`。
- 已在 6 个文件的副本上验证 patch → check → restore 往返，还原后与原文件逐字节一致；补丁点用 dumpbin 反汇编复核。

## 真机验证（不用卸载 WinPcap）

`packet.dll` 不是 KnownDLL，程序目录比 System32 先被搜索。把 Npcap 的 32 位
`C:\Windows\SysWOW64\Npcap\Packet.dll` 复制到 eNSP 根目录（`eNSP_Client.exe` 旁边），
eNSP 就改用 Npcap，系统里的 WinPcap 原样不动；删掉这份副本即还原。用 pcapprobe 验证过这个办法：
同目录放 Npcap 的 `Packet.dll` 后 `PacketGetVersion()` 返回 `"1.89"`，13 块网卡都列得出来。

1. 关闭 eNSP，复制 Npcap 的 `Packet.dll` 到 eNSP 根目录 → 打开 Cloud 配置，应复现"只剩 UDP"。
2. 关闭 eNSP，管理员运行 `python patches\patch_pcap_version.py` → 再打开 Cloud 配置，应能看到本机网卡。
3. 把 Cloud 桥接到本机网卡（或 host-only），与设备双向 ping、抓包对照。
4. 验证完：删除 eNSP 根目录里那份 `Packet.dll`。补丁可留（WinPcap 下无影响），也可 `--restore`。

还要观察：`\Device\NPF_Loopback` 这一项（没有 GUID）会不会出现在列表里、选中后是否无害。
