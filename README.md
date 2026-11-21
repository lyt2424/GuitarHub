# GuitarHub · 个人演出用吉他控制中枢

一个**不上架 App Store**、只为一个人（你）的舞台流程服务的 iOS App。

- **两个入口**：启动先选「电吉他模式」或「键盘模式」，两者互斥，同一时刻只连一种设备。
- **电吉他模式**：音色名可改中文、颜色块一眼看开关（开=彩色，关=灰）、点块即切换、右上角小图标调参数；设备用标题栏菜单切换（Spark / Pulze / 以后新增的）。
- **键盘模式**：KORG Module 的大字音色名与音色表。
- **iPhone 单机前台**：显示当前音色名、各模块开关与参数，接收蓝牙 MIDI 踏板，脚踩切换。
- **音箱/效果器**：Spark Mini（私有 BLE 协议，可读回完整音色）、Hotone Pulze Mini（官方 BLE MIDI，开关/音量/换音色）。
- **KORG Module Pro**：同一台 iPhone 上挂后台，本 App 用虚拟 MIDI 端口发 Program Change。这只是一种“能通最好”的附加能力；如果 Module 不接受虚拟端口，就只用本 App 管音箱与踏板。
- **可扩展**：设备能力由 JSON 配置描述，新增设备优先“加配置”，而不是改代码。

> **三种目标互斥**：Spark Mini、Pulze Mini、KORG Module 任一时刻只用其中一个（不会同时用两台）。
> 演出页顶部是三选一开关；切换时会自动断开上一台、并切换到对应的踏板组。
> 实际 BLE 连接只有两条：目标设备 + MIDI 踏板。

> 只能自己签安装（SideStore / AltStore / Xcode），详见 [构建与安装](docs/04-构建与安装.md)。

---

## 现在能做什么

| 功能 | Spark Mini | Pulze Mini | KORG Module |
|---|---|---|---|
| 显示当前音色名 | ✅ 从音箱读回 | ✅ 用本地音色表记录 PC | ✅ 用本地槽位表显示 |
| 显示模块开关状态 | ✅（7 个槽位） | ✅（NR/PRE/AMP/CAB/EQ/Fx1/Fx2） | — |
| 修改参数数值 | ✅ 单参数命令 | ⚠️ 仅音量（官方 MIDI 未开放单块参数） | ⚠️ 只能选音色（Module 无参数回读） |
| 切换音色 | ✅ | ✅ | ✅ Program Change |
| 蓝牙 MIDI 踏板 | ✅ | ✅ | ✅ |
| 双向通信 | ✅ 读回状态 | ⚠️ 只发不收 | ⚠️ 只发不收 |

图例：✅ 完整可用；⚠️ 受设备官方协议限制。

## KORG 的定位（不依赖 iPad）

KORG Module 不对外广播“当前音色名”，也没有参数回读，所以 App 只能以自己维护的音色表为准。
唯一尝试是**同一台 iPhone**：本 App 创建虚拟 MIDI 端口 `GuitarHub`，Module 打开 Background Audio 在后台运行，并在 MIDI 输入里选中它。

如果 Module 的 MIDI 输入列表里没有 `GuitarHub`（即它不接受虚拟端口），那就放弃这一项：
本 App 继续负责音箱控制、音色显示和踏板，Module 照常在后台放音、手动换音色。不会为此引入 iPad 或任何第二台设备。

## 目录

```
ios/                  Xcode 工程（XcodeGen 生成）
  GuitarHub/          主 App：BLE、协议编解码、踏板路由、界面
  GuitarHub/Resources/Profiles/   设备协议配置（JSON）
tools/                PDF 提取、BLE 探测、Spark 帧格式自检
docs/                 可行性、架构、协议笔记、构建、测试
.github/workflows/    GitHub Actions：出未签名 IPA
```

## 快速开始

```bash
# 需要 macOS + Xcode 15+
brew install xcodegen
cd ios && xcodegen generate
open GuitarHub.xcodeproj
```

没有 Mac 也可以：推送到 GitHub，Actions 会自动产出一个未签名 IPA，再用 SideStore 安装。详见 [构建与安装](docs/04-构建与安装.md)。

## 已知限制（先说清楚）

- Spark 部分依据公开逆向资料实现，**首次实机需要按[测试清单](docs/05-测试清单与新增设备.md)校验**；若某些固件命令字不同，改 `SparkCodec` 里的常量即可。
- Pulze 官方 MIDI 只开放块开关/音量/换音色/速度，**不能改单块参数**；要改参数只能逆向 Pulze Editor 的私有 BLE 协议（工具已备）。
- KORG Module 不接受"设置参数"，只按 Set List 顺序响应 Program Change；显示名由你在 App 里维护。
- 免费 Apple ID 签名 7 天过期，需要重新签名；付费开发者账号可 1 年。
- 本仓库不包含任何厂商固件、音色库或闭源二进制。

## 文档

1. [可行性与边界](docs/01-可行性与边界.md)
2. [架构与数据流](docs/02-架构与数据流.md)
3. [协议笔记（Spark / Pulze / KORG / BLE MIDI）](docs/03-协议笔记.md)
4. [构建与安装](docs/04-构建与安装.md)
5. [实机测试清单与新增设备](docs/05-测试清单与新增设备.md)
6. [GitHub Actions 编译 + Windows 安装 操作手册](docs/06-GitHub-Actions操作手册.md)
