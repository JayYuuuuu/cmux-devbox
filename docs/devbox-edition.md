# cmux DevBox 定制版

基于 [cmux](https://github.com/manaflow-ai/cmux) `v0.65.2`（`9d01f956c51cd895e10e7d56b6dd7b5f6fcce625`）的个人定制版：专门用来从 Mac 通过普通 SSH 连远程开发机、在远端跑 Claude Code。补丁集中在分支 `devbox-065` 上，每个提交只做一件事。`devbox-064` 是更早停在 `v0.64.25` 上的版本（`devbox.11`）；回退到 0.64 是为了躲开 0.65.0 首次粘新截图超时的问题，0.65.2 调整了图片准备阶段的超时计算并自带中文字体排版；是否解决旧版首次截图故障仍需实机验收，所以 0.65 线不再 fork Ghostty 子模块。非官方版本，与 Manaflow 无关；许可证沿用上游（macOS 客户端 GPL-3.0-or-later）。

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
| 远程图片粘贴 | 普通 SSH 和 `cmux ssh` 都沿用旧版的一次 SCP 直传 `/tmp/cmux-paste-<会话>-<uuid>.png`，不建私有目录、不追加权限校验连接。插入远端**绝对路径**，Claude Code 可直接识别为 `[Image #1]`。超时按大小算（10 秒 + 每 100KB 1 秒，最多 45 秒），超时自动重试一次。 |
| 无 Cloud / 账号 / 手机 | 单一开关 `CmuxDevBoxEdition`（按 bundle id 生效）：复用 MDM 策略关掉 Cloud、远控配对、Iroh、设备发现；钉死相关远程 feature flag；登录入口、账号命令、手机通知转发、设置里的 账户/手机/Cloud/电脑/网络 页全部隐藏。 |
| 独立身份 | bundle id `com.cmuxterm.app.staging.devbox`，名字 `cmux DevBox`，socket `/tmp/cmux-staging-devbox.sock`，会话/历史/配置按 bundle id 隔离；与官方 `cmux.app` 同时运行互不影响。 |
| 自己的更新通道 | Sparkle 只读本仓库最新 Release 里的 `appcast.xml`，安装包必须带本版的 EdDSA 签名，官方 cmux 的更新包会被拒绝；应用用固定的自签名证书签名，更新后系统权限不丢。 |
| 出厂设置 | `CmuxDevBoxEdition.defaultSettings` 注册为默认值（深色外观、选中即复制并提示、复制时合并硬换行、退出和关闭工作区不确认），用户改过的值和 `cmux.json` 仍优先；本版自己的 `config.ghostty` 不存在时写入一份起始终端配置（Everforest Dark Hard、方块不闪光标、标签栏字号 11、不透明背景）。 |
| Shift+回车换行 | 终端里 Shift+回车发送 ESC CR（与 Option+回车相同），经 SSH 和未开 extended-keys 的 tmux 到远端 Claude Code 仍是换行而不是提交；用户自己的 keybind 优先。 |
| 中文界面数值标签 | 89 条中英文相同的文案（单位、数值格式、品牌名）补上简体中文条目，设置里滑块旁不再显示内部键名。 |
| 配置报错过滤 | 切换浅/深色时 Ghostty 重放配置产生的不带文件位置的报错，若针对 cmux 自己的设置项（如 `surface-tab-bar-font-size`）也不再弹「配置错误」。 |
| 关于窗口 | 显示 `cmux DevBox`、定制版版本号和上游基线。 |

直接上传 `/tmp` 仅由 DevBox 身份启用，其他版本保留上游行为。上传失败或取消时回收本次文件。旧远程会话协调器在结束时清理本会话文件；普通 SSH 和新终端通道的成功文件留在远端 `/tmp`，沿用远端自己的临时文件清理安排。普通 SSH 上传仍沿用上游的进程启动方式；超时和重试不能据此证明旧故障的成因已确定或已修复。

仍与所有 cmux 渠道共享（上游设计如此）：`~/.config/cmux/` 下的设置文件、`~/Library/Application Support/cmux/` 下的搜索库等少量全局文件。

## 使用

1. 打开后照常 `ssh <你的主机别名>`（读 `~/.ssh/config`，别名、密钥、端口、ProxyJump 都沿用，不需要 `cmux ssh`）。
2. 在远端 Claude Code 里按 Command+V 粘贴截图/图片：cmux 用一次 SCP 上传到远端 `/tmp/`，再把绝对路径粘进去，Claude Code 显示 `[Image #1]`。
3. 失败时 cmux 会提示上传失败的原因（scp 的报错原文）。常见原因：SSH 需要交互输入密码/2FA（后台上传用 BatchMode，答不了，请用密钥登录）、远端磁盘满、连接已断。
4. 恢复 Claude Code 会话：远端 `claude --resume` 或 `claude --continue`，与终端无关。

Computer Use 等需要系统权限的功能：ad-hoc 签名每次重建都会变，权限要重新授权。

## 自己构建

前置：macOS 14+、完整 Xcode（已同意许可：`sudo xcodebuild -license accept`）、Metal 工具链（`xcodebuild -downloadComponent MetalToolchain`）、Rust（rustup）、Zig 0.16.x（在 PATH 里）。不需要 Go：WireGuard 只给 Cloud 隧道用，构建时用 stub。

```bash
git clone --branch devbox-065 --recurse-submodules https://github.com/JayYuuuuu/cmux-devbox.git
cd cmux-devbox
./scripts/setup.sh
./scripts/build-devbox.sh               # 本机架构；--universal 出通用版
```

产物在 `~/cmux-devbox-build/out/`：`cmux DevBox.app` 和 ZIP。脚本不启动、不退出、不替换任何正在运行的 cmux。通过 SSH 构建时脚本已用 netrc 代替钥匙串取包凭据，避免卡死。首次全量构建约 17 分钟（M 系列 Mac mini，单架构），之后增量约 1 分钟。

## 发布新版本（维护者）

在构建 Mac 上，代码已提交并推送到 `devbox-065` 后：

```bash
./scripts/release-devbox.sh <n> notes.md   # n = 上一版的 devbox 序号 + 1
```

它会仅编苹果芯片版、用固定证书签名、给 ZIP 加 EdDSA 签名、生成 `appcast.xml`，以 `v<上游版本>-devbox.<n>` 发 Release，最后回读线上 appcast 和 ZIP 校验。版本号：显示 `<上游>-devbox.<n>`，内部 build 号 `<上游 build>.<n>`；上游升级后 build 号自然变大，`n` 可以从 1 重新开始。

构建 Mac 上的一次性准备（都在 `~/.config/cmux-devbox/`，权限 600，**不进仓库**）：
- 签名钥匙串 `~/Library/Keychains/cmux-devbox-signing.keychain-db`，内含自签名身份「cmux DevBox Code Signing」，密码在 `signing-keychain-password`，打包脚本自动解锁，无需弹框授权。
- Sparkle 私钥 `sparkle-ed25519-private.key`（对应公钥写在 `build-devbox.sh`）。

🔴 两者都要离线备份。丢了签名证书：更新后系统权限要重新授权；丢了 Sparkle 私钥：已安装的副本再也收不到更新，只能手动重装换新公钥的版本。

## 升级上游

不跟 main。选定新的稳定标签后，在新标签上 cherry-pick `devbox-065` 的提交，解决冲突，把 `build-devbox.sh` 里的 `UPSTREAM_TAG` 改成新标签，跑 `python3 scripts/verify-local.py --affected <新标签>` 和相关包测试（`CmuxRemoteSession`、`CmuxSettings`、`CmuxSettingsUI`），重新构建，再按下面的验收清单走一遍。

## 验收清单

- 普通 `ssh <主机>` → Claude Code → Command+V 截图 → `[Image #1]`，Claude 能描述图片内容。
- 同一会话连续粘 3 张图，顺序正确。
- 上传中切到别的工作区，图片不会粘到新工作区。
- 断网/远端不可达时有报错，不插入路径。
- 普通文本、多行文本粘贴不变。
- 设置、侧栏、命令面板、菜单里没有 Cloud / 登录 / 手机配对入口。
- 与官方 cmux 同时开着，两边互不影响。
