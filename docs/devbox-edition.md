# cmux DevBox 定制版

基于 [cmux](https://github.com/manaflow-ai/cmux) `v0.65.0`（`dda24fbd2250dfacf41bf5e8e3d20d488acf6182`）的个人定制版：专门用来从 Mac 通过普通 SSH 连远程开发机、在远端跑 Claude Code。补丁集中在分支 `devbox-custom` 上，每个提交只做一件事。非官方版本，与 Manaflow 无关；许可证沿用上游（macOS 客户端 GPL-3.0-or-later）。

## 下载安装

1. 从 [Releases](https://github.com/JayYuuuuu/cmux-devbox/releases/latest) 下载 `cmux-DevBox-*-universal.zip`（Apple 芯片和 Intel 通用，需要 macOS 14+）。
2. 解压，把 `cmux DevBox.app` 拖进「应用程序」。
3. 应用是 ad-hoc 签名、未经 Apple 公证，浏览器下载的会被拦（提示「已损坏」或「无法验证开发者」）。在终端执行一次：

   ```bash
   xattr -cr "/Applications/cmux DevBox.app"
   ```

4. 打开即可，可以和官方 cmux 同时运行。

## 和官方版的区别

| 改动 | 说明 |
| --- | --- |
| 远程图片粘贴 | 普通 SSH 和 `cmux ssh` 上传后，插入远端**绝对路径**（如 `/home/<用户>/.cache/cmux/paste/<会话>/cmux-paste-<uuid>.png`），而不是 `\~/.cache/...`。Claude Code 不展开 `~`，只有绝对路径才会变成 `[Image #1]`。远端是 macOS 时上传最后一步的 `chmod --` 报错也一并修了。 |
| 无 Cloud / 账号 / 手机 | 单一开关 `CmuxDevBoxEdition`（按 bundle id 生效）：复用 MDM 策略关掉 Cloud、远控配对、Iroh、设备发现；钉死相关远程 feature flag；登录入口、账号命令、手机通知转发、设置里的 账户/手机/Cloud/电脑/网络 页全部隐藏。 |
| 独立身份 | bundle id `com.cmuxterm.app.staging.devbox`，名字 `cmux DevBox`，socket `/tmp/cmux-staging-devbox.sock`，会话/历史/配置按 bundle id 隔离；与官方 `cmux.app` 同时运行互不影响。 |
| 不自动更新 | staging 前缀的 id 让 Sparkle 永不检查/安装；打包时还删掉了更新源和公钥。升级请回本仓库下载新版。 |
| 关于窗口 | 显示 `cmux DevBox`、定制版版本号和上游基线。 |

仍与所有 cmux 渠道共享（上游设计如此）：`~/.config/cmux/` 下的设置文件、`~/Library/Application Support/cmux/` 下的搜索库等少量全局文件。

## 使用

1. 打开后照常 `ssh <你的主机别名>`（读 `~/.ssh/config`，别名、密钥、端口、ProxyJump 都沿用，不需要 `cmux ssh`）。
2. 在远端 Claude Code 里按 Command+V 粘贴截图/图片：cmux 先上传到远端 `~/.cache/cmux/paste/`，再把绝对路径粘进去，Claude Code 显示 `[Image #1]`。
3. 失败时 cmux 会提示上传失败的原因（scp 的报错原文）。常见原因：SSH 需要交互输入密码/2FA（后台上传用 BatchMode，答不了，请用密钥登录）、远端磁盘满、连接已断。
4. 恢复 Claude Code 会话：远端 `claude --resume` 或 `claude --continue`，与终端无关。

Computer Use 等需要系统权限的功能：ad-hoc 签名每次重建都会变，权限要重新授权。

## 自己构建

前置：macOS 14+、完整 Xcode（已同意许可：`sudo xcodebuild -license accept`）、Metal 工具链（`xcodebuild -downloadComponent MetalToolchain`）、Rust（rustup）、Zig 0.16.x（在 PATH 里）。不需要 Go：WireGuard 只给 Cloud 隧道用，构建时用 stub。

```bash
git clone --branch devbox-custom --recurse-submodules https://github.com/JayYuuuuu/cmux-devbox.git
cd cmux-devbox
./scripts/setup.sh
./scripts/build-devbox.sh               # 本机架构；--universal 出通用版
```

产物在 `~/cmux-devbox-build/out/`：`cmux DevBox.app` 和 ZIP。脚本不启动、不退出、不替换任何正在运行的 cmux。通过 SSH 构建时脚本已用 netrc 代替钥匙串取包凭据，避免卡死。首次全量构建约 17 分钟（M 系列 Mac mini，单架构），之后增量约 1 分钟。

## 升级上游

不跟 main。选定新的稳定标签后，在新标签上 cherry-pick `devbox-custom` 的提交，解决冲突，跑 `python3 scripts/verify-local.py --affected <新标签>` 和相关包测试（`CmuxRemoteSession`、`CmuxSettings`、`CmuxSettingsUI`），重新构建，再按下面的验收清单走一遍。

## 验收清单

- 普通 `ssh <主机>` → Claude Code → Command+V 截图 → `[Image #1]`，Claude 能描述图片内容。
- 同一会话连续粘 3 张图，顺序正确。
- 上传中切到别的工作区，图片不会粘到新工作区。
- 断网/远端不可达时有报错，不插入路径。
- 普通文本、多行文本粘贴不变。
- 设置、侧栏、命令面板、菜单里没有 Cloud / 登录 / 手机配对入口。
- 与官方 cmux 同时开着，两边互不影响。
