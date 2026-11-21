# GitHub Actions 编译 + Windows 安装 操作手册

适用：**没有 Mac、也不用云 Mac 桌面**，只借用 GitHub 的 macOS 编译机（免费额度内）。

整个循环只有两步：**改代码 → GitHub Desktop 点 Push → 自动编译 → 下载 IPA → Sideloadly 装机**。

---

## 0. 准备清单

| 需要 | 说明 |
|---|---|
| GitHub 账号 | 免费即可，邮箱要验证 |
| GitHub Desktop | <https://desktop.github.com>（Windows 版） |
| iTunes | Apple 官网版（不是 Microsoft Store 版），给 Sideloadly 提供驱动 |
| Sideloadly | <https://sideloadly.io> |
| iPhone 数据线 | 首次安装必须插线 |

费用：私有仓库每月 2000 分钟免费额度，macOS 按 **10 倍**计费；一次构建约 3–5 分钟 → 计 30–50 分钟。
公开仓库的 Actions 对标准 runner 免费不限时。按每月 20 次构建算，私有仓库额度够用。

---

## 1. 把代码传到 GitHub

1. 安装 GitHub Desktop，用 GitHub 账号登录。
2. 菜单 **File → Add local repository…**
3. 选择目录：`C:\Users\11131\Documents\deepseek-harness\default-workspace`
4. 提示 “not a Git repository” 时点 **create a repository**：
   - Name：`GuitarHub`
   - 不勾 “Initialize with README”（仓库里已经有）
   - 点 **Create Repository**
5. 右上角 **Publish repository**：
   - 想省额度就取消勾选 “Keep this code private”（公开仓库 Actions 免费不限）
   - 在意隐私就保持私有（额度也够）
   - 点 **Publish**
6. 等上传完成。仓库总共约 214 KB / 40 个文件；`research/` 里的大 PDF 已被 `.gitignore` 排除。

> 以后每次我改完代码，你只需要：打开 GitHub Desktop → 左下角写一句说明 → **Commit to main** → **Push origin**。

---

## 2. 触发编译

1. 打开 `https://github.com/你的用户名/GuitarHub` → 顶部 **Actions**。
2. 首次会提示 “Workflows aren’t being run on this repository” → 点 **I understand my workflows, go ahead and enable them**。
3. 左侧选 **build-unsigned-ipa** → 右侧 **Run workflow** → 分支选 `main` → **Run workflow**。
   （如果第 5 步 Publish 后已经自动跑了一次，可以跳过手动触发。）
4. 等 3–6 分钟，出现绿色 ✓。

---

## 3. 下载 IPA

1. 点进这次运行记录。
2. 页面底部 **Artifacts** → 下载 `unsigned-ipa.zip`。
3. 解压，得到 `GuitarHub-unsigned.ipa`。

这个 IPA 是**未签名**的，下一步由 Sideloadly 用你的 Apple ID 签名。

---

## 4. 装到 iPhone（Windows）

1. 安装 Apple 官网版 iTunes，打开一次，确认能识别设备。
2. 安装 Sideloadly。
3. iPhone 插 USB，解锁，手机上点“信任此电脑”。
4. 打开 Sideloadly：
   - 左上角确认已选中你的 iPhone
   - 把 `GuitarHub-unsigned.ipa` 拖进 **IPA** 框
   - **Apple ID** 填你的 Apple ID
   - 点 **Start**
5. 按提示输入 Apple ID 密码；如果开了双重认证，手机会弹出 6 位验证码，填进去。
   （Sideloadly 直接与 Apple 的开发者接口通信申请免费证书，不经过第三方服务器。）
6. 装完后在手机上：**设置 → 通用 → VPN与设备管理** → 点你的 Apple ID → **信任**。
7. iOS 16 及以上还需要：**设置 → 隐私与安全性 → 开发者模式** → 打开 → 重启手机。
   如果找不到这个菜单，先打开一次 App（会提示“需要开发者模式”），菜单就会出现。

---

## 5. 首次打开

1. 允许“蓝牙”权限（必须）。
2. 设置 → 设备配置，确认看到 `Spark Mini` 与 `Pulze Mini`。
3. 设备页 → 搜索 → 连接音箱。
4. 踏板页 → 搜索 → 连接踏板。
5. 按 `docs/05-测试清单与新增设备.md` 从 A 跑到 F。

---

## 6. 每 7 天续签

免费 Apple ID 的证书 7 天过期，App 会打不开（闪退）。到期前：

1. iPhone 插 USB，打开 Sideloadly。
2. 拖入同一个 IPA（留着别删），填 Apple ID，Start。
3. 覆盖安装，**预设库数据保留**。
4. 千万不要删除 App —— 删除会清空数据。

想脱离电脑续签，可以进一步用 **SideStore**（需要 `jitterbugpair` 生成配对文件 + 手机上装 StosVPN），配置一次后手机自己续签。

---

## 7. 编译失败了怎么办

第一次构建大概率会有 Swift 编译错误（这份代码没有在真机/编译器上验证过）。

1. 在 Actions 运行页，点开红色的 **Build GuitarHub (unsigned)** 步骤。
2. 向下找 `error:` 开头的行，**复制最后 30–50 行**（包含文件路径和行号）。
3. 发给我。我改本地文件。
4. 你在 GitHub Desktop 里 Commit → Push，Actions 会自动重跑。

这就是为什么推荐 GitHub Desktop：一轮修复只需要你两次点击。

---

## 8. 已知的“第一次可能踩”的点

| 现象 | 原因 / 处理 |
|---|---|
| `xcodegen: command not found` | 不会发生，workflow 里已经 `brew install xcodegen` |
| `Cannot find 'X' in scope` | 少 import 或拼写错误，把报错发我 |
| `No such module 'Combine'` | 不会发生，Combine 是系统框架 |
| `Signing for "GuitarHub" requires a development team` | 不会发生，CI 用 `CODE_SIGNING_ALLOWED=NO` |
| `GuitarHub.app` 找不到 | 说明编译失败，看上面步骤 |
| 装完闪退 | 证书没信任 / 没开开发者模式 / 签名过期 |
| 搜不到 Spark | 音箱被官方 App 占用，或没在可连接状态 |
