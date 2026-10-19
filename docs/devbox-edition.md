# cmux DevBox 定制版

基于 [cmux](https://github.com/manaflow-ai/cmux) `v0.64.25` 的个人定制版：专门用来从 Mac 通过普通 SSH 连远程开发机、在远端跑 Claude Code。补丁集中在分支 `devbox-064` 上，每个提交只做一件事。`devbox.1`~`devbox.10` 曾基于 `v0.65.0`（分支 `devbox-custom`）；0.65 底的版本普通 SSH 粘图常常「新截图第一次粘贴卡住到超时、再粘就成功」（失败那次远端会话 0.2 秒就结束且没有文件，根因未查明，官方 0.64 不出现），`devbox.11` 起回到 0.64 线，只把 0.65 的中文字体显示改进（Ghostty 按终端格子宽度给 CJK 回退字体定尺寸）搬过来。非官方版本，与 Manaflow 无关；许可证沿用上游（macOS 客户端 GPL-3.0-or-later）。


`0.64.25-devbox.12` 是面向 `0.65.2-devbox.2` 的恢复更新：程序代码和 Ghostty 字体渲染保持 `0.64.25-devbox.11`，仅调整发布编号与更新入口。内部版本 `112.12` 高于 `111.2`，因此可以通过应用内更新安装；GitHub Latest 显式指向恢复版本。0.65.2 上报告的粘图卡住仍未修复，该版本通过回到旧基线避开此次回归。
## 下载安装

1. 下载 [cmux-DevBox.zip](https://github.com/JayYuuuuu/cmux-devbox/releases/latest/download/cmux-DevBox.zip)（永远是最新版；只支持 Apple 芯片，需要 macOS 14+；devbox.7 及以前是通用版）。
2. 解压，把 `cmux DevBox.app` 拖进「应用程序」。
3. 应用用自签名证书签名、未经 Apple 公证，浏览器下载的会被拦（提示「已损坏」或「无法验证开发者」）。首次安装在终端执行一次：

   ```bash
   xattr -cr "/Applications/cmux DevBox.app"
   ```

4. 打开即可，可以和官方 cmux 同时运行。之后的新版本由应用内更新安装（菜单「检查更新」，或每天自动检查后提示），不用再手动下载。

`0.65.0-devbox.3` 及更早的包没有更新通道，要手动装一次 `devbox.4` 或更新版本，之后才能自动更新。

## 和官方版的区别

| 改动 | 说明 |
| --- | --- |
| 远程图片粘贴 | 沿用 0.64 原版：每张图一次 scp 传到远端 `/tmp/cmux-drop-<uuid>.png`，插入这个绝对路径（Claude Code 不展开 `~`，只有绝对路径才会变成 `[Image #1]`）。 |
| 中文字体显示 | Ghostty 子模块指向 `JayYuuuuu/ghostty` 的 `devbox-064` 分支：0.64 用的 Ghostty 加上上游两个提交，让中文等 CJK 回退字体按终端格子宽度排版（0.65 的显示效果）。 |
| 无 Cloud / 账号 / 手机 | 单一开关 `CmuxDevBoxEdition`（按 bundle id 生效）：复用 MDM 策略关掉 Cloud、远控配对、Iroh、设备发现；钉死相关远程 feature flag；登录入口、账号命令、手机通知转发、设置里的 账户/手机/Cloud/电脑/网络 页全部隐藏。 |
| 独立身份 | bundle id `com.cmuxterm.app.staging.devbox`，名字 `cmux DevBox`，socket `/tmp/cmux-staging-devbox.sock`，会话/历史/配置按 bundle id 隔离；与官方 `cmux.app` 同时运行互不影响。 |
| 自己的更新通道 | Sparkle 只读本仓库最新 Release 里的 `appcast.xml`，安装包必须带本版的 EdDSA 签名，官方 cmux 的更新包会被拒绝；应用用固定的自签名证书签名，更新后系统权限不丢。 |
| 出厂设置 | `CmuxDevBoxEdition.defaultSettings` 注册为默认值（深色外观、选中即复制并提示、复制时合并硬换行、退出和关闭工作区不确认），用户改过的值和 `cmux.json` 仍优先；本版自己的 `config.ghostty` 不存在时写入一份起始终端配置（Everforest Dark Hard、方块不闪光标、不透明背景）。 |
| Shift+回车换行 | 终端里 Shift+回车发送 ESC CR（与 Option+回车相同），经 SSH 和未开 extended-keys 的 tmux 到远端 Claude Code 仍是换行；用户自己的 keybind 优先。 |
| 中文界面数值标签 | 中英文相同的文案（单位、数值格式、品牌名）补上简体中文条目，设置里不再显示内部键名。 |
| 关于窗口 | 显示 `cmux DevBox`、定制版版本号和上游基线。 |

仍与所有 cmux 渠道共享（上游设计如此）：`~/.config/cmux/` 下的设置文件、`~/Library/Application Support/cmux/` 下的搜索库等少量全局文件。

## 使用

1. 打开后照常 `ssh <你的主机别名>`（读 `~/.ssh/config`，别名、密钥、端口、ProxyJump 都沿用，不需要 `cmux ssh`）。
2. 在远端 Claude Code 里按 Command+V 粘贴截图/图片：cmux 先上传到远端 `/tmp/cmux-drop-<uuid>`，再把绝对路径粘进去，Claude Code 显示 `[Image #1]`。远端不自动删，建议开发机定时清理一天前的。
3. 失败时 cmux 会提示上传失败的原因（scp 的报错原文）。常见原因：SSH 需要交互输入密码/2FA（后台上传用 BatchMode，答不了，请用密钥登录）、远端磁盘满、连接已断。
4. 恢复 Claude Code 会话：远端 `claude --resume` 或 `claude --continue`，与终端无关。

Computer Use 等需要系统权限的功能：ad-hoc 签名每次重建都会变，权限要重新授权。

## 自己构建

前置：macOS 14+、完整 Xcode（已同意许可：`sudo xcodebuild -license accept`）、Metal 工具链（`xcodebuild -downloadComponent MetalToolchain`）、Rust（rustup）、Zig 0.16.x（在 PATH 里）。不需要 Go：WireGuard 只给 Cloud 隧道用，构建时用 stub。

```bash
git clone --branch devbox-064 --recurse-submodules https://github.com/JayYuuuuu/cmux-devbox.git
cd cmux-devbox
./scripts/setup.sh
./scripts/build-devbox.sh               # 本机架构；--universal 出通用版
```

产物在 `~/cmux-devbox-build/out/`：`cmux DevBox.app` 和 ZIP。脚本不启动、不退出、不替换任何正在运行的 cmux。通过 SSH 构建时脚本已用 netrc 代替钥匙串取包凭据，避免卡死。首次全量构建约 17 分钟（M 系列 Mac mini，单架构），之后增量约 1 分钟。

## 发布新版本（维护者）

在构建 Mac 上，代码已提交并推送到 `devbox-064` 后：

```bash
./scripts/release-devbox.sh <n> notes.md   # n = 上一版的 devbox 序号 + 1
```

它会编通用版、用固定证书签名、给 ZIP 加 EdDSA 签名、生成 `appcast.xml`，以 `v<上游版本>-devbox.<n>` 发 Release，最后回读线上 appcast 和 ZIP 校验。版本号：显示 `<上游>-devbox.<n>`，内部 build 号 `<上游 build>.<n>`；上游升级后 build 号自然变大，`n` 可以从 1 重新开始。

构建 Mac 上的一次性准备（都在 `~/.config/cmux-devbox/`，权限 600，**不进仓库**）：
- 签名钥匙串 `~/Library/Keychains/cmux-devbox-signing.keychain-db`，内含自签名身份「cmux DevBox Code Signing」，密码在 `signing-keychain-password`，打包脚本自动解锁，无需弹框授权。
- Sparkle 私钥 `sparkle-ed25519-private.key`（对应公钥写在 `build-devbox.sh`）。

🔴 两者都要离线备份。丢了签名证书：更新后系统权限要重新授权；丢了 Sparkle 私钥：已安装的副本再也收不到更新，只能手动重装换新公钥的版本。

## 长期升级约束（2026-10-19 用户确认）

中文保留 `0.64.25-devbox.12` 的视觉效果：字形尽量撑满两个终端字符格，不采用上游向英文字母高度收缩的限制。以后升级不能仅凭“上游已有 CJK 修复”就撤掉现有 Ghostty 补丁；同一配置、同一屏幕下对照中文、英文和中英混排，由用户确认后才能替换。字体变小的具体运行时成因仍未完成实测归因，代码差异仅作为调查线索。

远程截图粘贴是升级的首要验收项，继续使用每张图一次 SCP 直传临时目录、插入绝对路径的方式。实机验收使用 Codex；构建成功、单元测试或另一台机器通过均不能替代用户常用设备的实际粘图验证。用户已确认安装 `0.64.25-devbox.12` 后文字样式和截图粘贴恢复正常；这是用户验收回报，不是新增自动化测量。

## 升级上游

不跟 main。选定新的稳定标签后，在新标签上 cherry-pick `devbox-064` 的提交（Ghostty 子模块也要在新标签用的 Ghostty 上重放 `devbox-064` 分支的提交），解决冲突，把 `build-devbox.sh` 里的 `UPSTREAM_TAG` 改成新标签，跑 `python3 scripts/verify-local.py --affected <新标签>` 和相关包测试（`CmuxRemoteSession`、`CmuxSettings`、`CmuxSettingsUI`），重新构建，再按下面的验收清单走一遍。

## 验收清单

- 普通 `ssh <主机>` → Claude Code → Command+V 截图 → `[Image #1]`，Claude 能描述图片内容。
- 同一会话连续粘 3 张图，顺序正确。
- 上传中切到别的工作区，图片不会粘到新工作区。
- 断网/远端不可达时有报错，不插入路径。
- 普通文本、多行文本粘贴不变。
- 设置、侧栏、命令面板、菜单里没有 Cloud / 登录 / 手机配对入口。
- 与官方 cmux 同时开着，两边互不影响。
