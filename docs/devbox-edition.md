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
| 出厂设置 | `CmuxDevBoxEdition.defaultSettings` 注册为默认值（深色外观、极简模式、选中即复制并提示、复制时合并硬换行、退出和关闭工作区不确认），用户改过的值和 `cmux.json` 仍优先；已有安装第一次运行默认极简模式的版本时一次性切到极简模式（标记 `cmux.devbox.minimalModeDefault.v1`），之后用户自己切回标准模式会保留；极简模式下本版仍在侧栏底部显示「有可用更新」，否则新版本没有任何提示。侧栏默认宽 280pt（上游 240）；已有安装第一次运行这个版本时，停在旧默认 240 没拖过的窗口一次性加宽到 280（标记 `cmux.devbox.sidebarWidth280.v1`），拖过的保留。本版自己的 `config.ghostty` 不存在时写入一份起始终端配置（Everforest Dark Hard、方块不闪光标、不透明背景）。 |
| Shift+回车换行 | 终端里 Shift+回车发送 ESC CR（与 Option+回车相同），经 SSH 和未开 extended-keys 的 tmux 到远端 Claude Code 仍是换行；用户自己的 keybind 优先。 |
| 中文界面数值标签 | 中英文相同的文案（单位、数值格式、品牌名）补上简体中文条目，设置里不再显示内部键名。 |
| 关于窗口 | 显示 `cmux DevBox`、定制版版本号和上游基线。 |
| 侧边栏 Claude 用量徽章 | 远端 Claude Code 状态栏把 5 小时 / 每周用量（`rate_limits`，长期 token 登录也有）写成 OSC 777 通知，标题 `cmux-devbox-claude-usage`；本版拦下它不弹通知，存成该工作区的状态项 `devbox.claude_usage`，画成「账号名 + 两个环形用量 + 距重置时间」徽章，悬停看具体重置时刻。远端配置见下方「Claude 用量徽章」。 |
| 内置团队面板 | 左侧栏默认是软件自带的团队面板（自定义侧边栏 `devbox`，源文件 `Resources/devbox-sidebars/devbox.js`，由 `build-devbox.sh` 打进包内 `Contents/Resources/devbox-sidebars`）：按账号分组的会话卡片（5 小时 / 本周用量，窗口过了一成后，进度格里从已用到「平均用的话现在该到这」的一段调亮，百分比旁标「充足」或「偏快」；照目前速度会在重置前用完就变琥珀色并多一行「照这速度 X 用完」，本周额度还给出每天别超多少、各会话状态、Claude / Codex 标签、后台 shell 数），没开的会话一点就开。会话清单来自用户自己 `cmux.json` 里带 `devbox` 关键词、只有一个终端命令的工作区快捷入口（按快捷键顺序；标题去掉末尾数字就是账号分组），软件把它作为顶层数据 `devboxSessions`（`[{action, title, group, command}]`）交给面板；点没开的会话时面板调用 socket 方法 `devbox.session.open {action_id}`，软件直接执行那条快捷入口（和按快捷键同一条路径，只接受面板列出的入口），所以面板本身不含任何机器信息。同名用户文件 `~/.config/cmux/sidebars/devbox.js` 会被忽略（旧装法写过，防止挡住更新）；自己试验请换别的名字。.41 起面板脚本也从 devbox 取：在 devbox 的仓库里跑 `scripts/devbox/publish-team-panel.sh`，把已提交的脚本放到 devbox 的 `~/.local/share/cmux-devbox/panel/devbox.js`；面板显示时软件每 5 分钟经一个已开的面板会话（前台是普通 `ssh`）另开非交互连接查一次，内容变了才传（gzip+base64），写进 `~/Library/Application Support/<bundle id>/devbox-panel/devbox.js` 原地热更新。脚本第一行必须是 `// cmux-devbox-panel rev=<n> min-build=<CFBundleVersion>`：每次改动加大 `rev`；用到只有新版软件才给的数据时把 `min-build` 提到那一版。软件只在远端 `rev` 比自带的高、且 `min-build` 不比自己新时用远端那份，否则（含没开会话、取失败）用自带那份。所以只改面板不用发版；改了软件给面板的数据才要发版，并把 `min-build` 提上去。左栏默认值是注册默认，用户在侧栏按钮里切换后以用户选择为准。 |
| 远端 agent 状态给自定义侧边栏 | 远端 Claude Code / Codex 的钩子在「提交提示词 / 等权限 / 干完 / 退出」时，用同一条 OSC 777 通道（标题仍是 `cmux-devbox-claude-usage`，正文 `v1 ev=agent st=… at=… agent=… who=… d=… t=…`，`d`/`t` 百分号编码）报告当前状态；本版存成状态项 `devbox.agent_activity`（不在侧栏显示成文字行），并和用量报告一起作为 `workspaces[i].devbox`（`usage`: who/label/email/payer/subscribed/cycle/h5/h5Reset/d7/d7Reset/at，`activity`: state/since/agent/who/dir/title/bg/codex/codexSince，`bg` 是 Claude Code 还在跑的后台 shell 数，`codex` 是它派出去仍在跑的 `codex exec` 个数，`codexSince` 是最早一个的开始时间）交给自定义侧边栏。正文不是用量报告，.15~.19 收到会静默丢弃，不弹通知。Ghostty 原本整个软件每秒只放行一条通知，同一秒内的第二条会被丢掉（Codex 提问时会话开始和开始干活两条同时发，几个会话同时报也会互吞）；DevBox 的 Ghostty 分支让这个保留标题的报告绕过限流、也不占限流名额。终端把通知正文限制在 255 字节内，上报脚本会先截短提示词；解析时遇到被截断的半截编码会丢掉残缺部分。重启恢复会话时保留用量报告（自带重置时间），丢掉 agent 状态（关软件期间结束的回合会一直显示「干活中」）。远端配置见下方「agent 状态钩子」。 |
| 卡片外观 | 工作区内容画成一张圆角卡片（四周留 8pt、内收 4pt、连续曲线圆角 12pt、上亮下暗的细光边、软阴影），卡片外和标题栏一条用比终端底色深一档的底色；标题栏不再重复显示工作区名和文件夹图标。卡片内收量大于圆角切掉的部分，所以浮在上层的终端不会盖住圆角和描边。没有显式设置 `workspaceColors.selectionColor` 时，侧栏选中行用比终端底色亮一档的颜色，跟着主题变。极简模式下由整张卡片升进标题栏那一条（离窗口顶边仍留 8pt），卡片里的工作区不再单独忽略顶部安全区，避免标签栏和顶边被推出窗口。`defaults write com.cmuxterm.app.staging.devbox devbox.cardChrome -bool false` 关闭。 |
| 窗口玻璃（.42+） | 版本注册 `chromeGlassOverOpaqueTerminal = true`：窗口用系统原生玻璃，窗口底层改铺「比终端深一档」的主题色（深色 88%、浅色 84%，系统玻璃会把自身色调冲淡成冷灰，所以颜色靠这层），侧栏背景透明露出它；终端卡片照旧铺不透明终端色，终端渲染和显卡占用不变。`defaults write com.cmuxterm.app.staging.devbox chromeGlassOverOpaqueTerminal -bool false` 关闭（关卡片外观时也要一起关，否则终端没有底色）。 |
| 终端透明开关（.42+） | 侧栏主题色点最右的水滴按钮：在 `config.ghostty` 末尾写入/删除 `# cmux devbox glass start` … `end` 托管块（`background-opacity = 0.8`），再发同一条重载通知；开着时卡片底色跟随半透明终端色，桌面会透进终端。默认关：每次输出都要重新合成玻璃，显卡占用变高、文字对比度下降。 |
| 胶囊标签（.42+） | 顶部标签用 Bonsplit 的 `Appearance.tabStyle = .capsule`（子模块指向 `JayYuuuuu/bonsplit` 分支 `devbox-064`）：选中标签是嵌在栏里的圆角胶囊（提亮底色、上亮下暗细边、轻阴影），悬停为淡胶囊，不再画顶部强调线、标签分隔线和栏底分隔线。其它版本保持 `.classic`。 |
| 命令面板外观（.42+） | 命令面板（含切换会话、重命名）画成 14pt 连续圆角的浮动卡片，底色取终端主题（深色提亮一档、浅色近白保留暖调），细光边加深软阴影；搜索框是带放大镜的内凹圆角框，去掉分隔线；行高 28pt，选中行是实心强调色胶囊（白字、匹配字加粗、快捷键标签半透明白），悬停为淡胶囊。 |
| 更新胶囊（.42+） | 侧栏「有可用更新」等状态胶囊改成玻璃提示条：材质底 + 20% 状态色 + 细光边 + 软阴影，「有可用更新」的文字和图标用强调色，其它状态用正文色。 |
| 侧栏主题按钮 | 侧栏底部一排八个色点（侧栏太窄时分两排）：深色 DevBox Mocha（Catppuccin Mocha）/ Tokyo Night（Night 版）/ Dracula / Forest（Forest 保持原样：Everforest Dark Hard，只把 ANSI 黑调成比底色亮一档），浅色 DevBox Paper（暖白纸墨，参考 Flexoki，彩色按 OKLCH 统一感知亮度与饱和度）/ Mist（冷调奶白蓝灰，Catppuccin Latte 色相）/ Ivory（温润暖灰白，几乎无彩的分层浅灰配琥珀色光标，OKLCH 底色 L0.956 C0.0045；所有字色在底色和浅一档面板上都 ≥4.6，并开 `minimum-contrast = 4.8`：DevBox 的 Ghostty 把 Claude Code / Codex 自定的偏淡字色按原色相加深到刚好够清楚，暗淡字先按实际显示的半透明效果算，不再像上游那样一律变纯黑/纯白） / Porcelain（瓷白：接近白但非纯白的 #fbf9f7（亮度与 #fafafa 相当，只留一丝暖意），正文、彩色与光标沿用 Ivory，同样开 minimum-contrast 4.8）；当前主题带彩色外圈。Sage（灰绿纸）、Sepia（电子书米黄）已从按钮移除，主题文件仍随包保留，已选它的配置照常可用。前三套深色基于各自官方 Ghostty 配色，仅把 ANSI 0 调成比底色亮一档、ANSI 8 注释灰提亮到至少 4.5:1，正文字色（含选中文字）统一用 Forest 的 #d3c6aa（对比度 8.4–10.1）；来源与许可见 `THIRD_PARTY_LICENSES.md`。原自配三套的完整配色备份与恢复方法在 [主题存档](devbox-theme-backups/README.md)。旧 Charcoal / Cinder / Cobalt 名称分别兼容新 Mocha / Tokyo Night / Dracula，已有配置无需改写就会用新配色，选中色点也对应新名。浅色主题背景都不是纯白，正文对比度约 10–12:1，普通彩色 ≥5:1、亮色 ≥4:1、注释灰约 3.6:1，避免浅底上的彩色字发虚。约定：深色主题的 ANSI 0 比底色亮一档、浅色主题的 ANSI 7 比底色深一档（深色约 1.1–1.2，浅色是底色向前景混 13%、约 1.26），远端 tmux 状态栏按深浅取这两色当底色，深浅两边都和终端底色分得开。浅色时团队面板从数据键 `devboxScheme`（"light"/"dark"，取终端主题明暗）切换选中描边、状态色和 Claude/Codex 标签的深色版。DevBox 主题放在 `Resources/devbox-themes`，由 `build-devbox.sh` 打进包内 Ghostty 主题目录。按钮与 `cmux themes set` 写同一个托管主题块（`CmuxGhosttyManagedThemeBlock`），再发同一条重载通知。侧栏要跟主题变色，`sidebarAppearance.matchTerminalBackground` 需为 true。 |
| 终端深浅报告 | 终端程序可以订阅深浅变化（mode 2031，`CSI ? 997 ; 1/2 n`），Claude Code 的 `auto` 主题靠它在会话中途换配色。DevBox 主题深浅两边写同一个主题，上游 Ghostty 这时不重算配置，终端回报一直停在配置加载时的深浅（一律报浅色）。DevBox 的 Ghostty 分支让回报跟终端自己的深浅走：切换时随消息带上新深浅，新建终端和配置更新时也以终端自己的深浅为准。经 tmux 时需要 tmux 3.6 以上才会转给窗格里的程序（3.4 只在连上时问一次底色）。多台电脑同时连一个 tmux 会话、深浅不一致时，原版 tmux 取它先找到的那台；`scripts/devbox/tmux` 的补丁改成跟最近使用（按键或切换深浅）的那台走，并等那台回了新底色再通知窗格，避免程序紧接着查底色拿到旧值。同目录另一个补丁把窗格里恰好 #f0f0f0 的底色（Claude Code 浅色主题垫在用户消息下的固定灰）换成终端的 ANSI 白，浅色主题下用户消息才和纸色分得开；Claude Code 在 tmux 里要设 `CLAUDE_CODE_TMUX_TRUECOLOR=1` 才发真彩色，否则降成 256 色的 255 号。Codex 不订阅深浅，启动时问一次底色，把输入框和用户消息的底色算成「底色向黑混 4%（浅）/向白混 12%（深）」的固定 RGB，之后切深浅不再变（深色页上留一条浅色带、字看不清）；第三个补丁让 tmux 记下回给窗格的底色，认出由它混出来的底色，存成新增的主题色 `themepanel`，每台终端按自己当前深浅画成 ANSI 7（浅，`light-theme-panel`）或 ANSI 0（深，`dark-theme-panel`）。改动对比的红绿底（GitHub 式浅色一套、深色一套）同理在启动时定死，补丁同样把它们存成主题色，按当前深浅取 Codex 自己的浅色或深色那套。其余字色（代码高亮、状态栏、快捷键提示等）tmux 按写入时告诉程序的深浅打标记，画到深浅相反的终端上时按 OKLab 把明暗翻转（与页面的明暗差不变，色相饱和度不变）；会跟 2031 重画的程序（Claude Code）重画后按新深浅标记，不受影响。 |

仍与所有 cmux 渠道共享（上游设计如此）：`~/.config/cmux/` 下的设置文件、`~/Library/Application Support/cmux/` 下的搜索库等少量全局文件。

## 使用

1. 打开后照常 `ssh <你的主机别名>`（读 `~/.ssh/config`，别名、密钥、端口、ProxyJump 都沿用，不需要 `cmux ssh`）。
2. 在远端 Claude Code 里按 Command+V 粘贴截图/图片：cmux 先上传到远端 `/tmp/cmux-drop-<uuid>`，再把绝对路径粘进去，Claude Code 显示 `[Image #1]`。远端不自动删，建议开发机定时清理一天前的。
3. 失败时 cmux 会提示上传失败的原因（scp 的报错原文）。常见原因：SSH 需要交互输入密码/2FA（后台上传用 BatchMode，答不了，请用密钥登录）、远端磁盘满、连接已断。
4. 恢复 Claude Code 会话：远端 `claude --resume` 或 `claude --continue`，与终端无关。

### Claude 用量徽章（远端配置）

1. 远端放 `scripts/devbox/claude-usage-report.mjs`，在 Claude Code 的 `statusLine` 命令里先 `input=$(cat)`，再后台执行 `printf '%s' "$input" | node claude-usage-report.mjs &`，原状态栏照旧用 `$input`。
2. 在 tmux 里用时需要 `set -g allow-passthrough on`（否则 tmux 会吞掉这段序列）。
3. 账号名取 `CLAUDE_USAGE_WHO`，没有就用 `CLAUDE_AS_NAME`、`USER`。同一会话内容不变时最多 5 分钟重发一次。可选 `CLAUDE_USAGE_LABEL` 给账号一个显示名（可带空格，报告里是 `lb=` 百分号编码，编码后最多 72 字符），邮箱取该会话 `.claude.json` 里的登录邮箱（`CLAUDE_CONFIG_DIR` 下，没设就是家目录），没有就用 `CLAUDE_USAGE_EMAIL`（报告里是 `em=`）。.37 起团队面板的账号卡片标题显示显示名、旁边显示邮箱，收到第一份报告前仍显示快捷入口分组名；旧版忽略这两个字段。可选 `CLAUDE_USAGE_PAYER`（付款的账号，可带空格，`pe=` 百分号编码）、`CLAUDE_USAGE_SUBSCRIBED`（订阅日期 yyyy-mm-dd，`ps=`）、`CLAUDE_USAGE_CYCLE`（m/y，也认 月/年，`pc=`）；.38 起卡片标题下多一行「付款」徽章 + 付款账号 + 下次续费日（按订阅日期和周期从 Mac 本地今天算，31 号订的在小月按月底续，7 天内显示「N天后续费」、3 天内变琥珀色）。正文超过 250 字节时依次丢掉 pc/ps/pe/em/lb。
4. 选中行上徽章用深色底、账号名白底反色，保证在选中色上可读。旧版把这类报告存成了普通通知，本版启动时从恢复的会话通知和通知历史里丢掉它们。
5. 只有该窗口里的 Claude Code 开着时会更新；关掉后徽章保留最后一次数值，过了重置时间自动显示 0%。侧边栏设置里隐藏「状态信息」时徽章一起隐藏。

### agent 状态钩子（远端配置）

1. 远端放 `scripts/devbox/agent-activity-report.py`，在 Claude Code 的 `UserPromptSubmit`、`PostToolUse`、`PermissionRequest`、`Notification`、`Stop`、`SessionStart`、`SessionEnd` 钩子里执行 `python3 agent-activity-report.py claude`（Codex 同名事件传 `codex`）。钩子 JSON 从标准输入读，任何错误都不会让钩子失败。
2. 和用量徽章一样直接写到 agent 所在的终端，tmux 里需要 `allow-passthrough on`；账号名取 `CLAUDE_AS_NAME`，没有就用 `CMUX_DEVBOX_WHO`、`USER`。
3. 每次钩子触发时数一下 Claude Code 进程下仍在运行的后台 shell（Bash 工具的 `shell-snapshots` 子进程；钩子触发时没有前台工具在跑），随报告带上 `bg=<n>`；后台任务结束时 Claude 会注入一条 `<task-notification>` 提示词，触发重新计数，这条不会替换任务标题。
4. Claude Code 自己用 Bash 调起的 `codex exec`（「指挥 Codex」）和 Claude 共用同一个终端，它的钩子不上报（否则会把 Claude 那一行改成 Codex 的状态，跑完还会变成「已退出」）；改由 Claude 的报告带上 `cx=<n> cxs=<开始时间>`，按 Claude 进程下最外层的 `codex` 进程计数；用 `nohup`/`setsid` 脱离出去的（父进程变成 init）靠进程环境里的 `CLAUDE_PID` 认回来。
5. 状态、提示词、后台 shell 数或 Codex 个数变了才发，否则最多 10 分钟重发一次；一次执行约 10 毫秒。
6. 这些序列在非 DevBox 终端（官方 cmux、DevBox .14 及更早）会显示成通知，只在大家都用 DevBox .15+ 的环境里打开。
7. 自定义侧边栏读法：`data.workspaces()` 每一项的 `devbox?.activity?.state`（`working` / `waiting` / `done` / `ended`）与 `devbox?.usage?.h5`、`devbox?.codexUsage`。
8. Codex 额度：每次钩子触发（Claude 或 Codex 都算）顺带读 `~/.codex/sessions` 最新会话日志里最后一条 `rate_limits`，按窗口长度把 300 分钟映射成 `h5`、一周映射成 `d7`（Pro 只有周窗口），发 `cx1 plan=… h5=… h5r=… d7=… d7r=… ob=<Codex 记录时间>`；数值不变时最多 10 分钟重发一次。本版（.29+）存成状态项 `devbox.codex_usage`（重启保留），作为 `workspaces[i].devbox.codexUsage`（plan/h5/h5Reset/d7/d7Reset/at）交给面板，面板取 `at` 最新的一份；更早的版本收到 `cx1` 静默丢弃。
9. Codex 重置卡（usage limit resets）：会话日志里没有，上报脚本在后台子进程里跑一次 `codex app-server`，发 `account/rateLimits/read`（与 Codex 用量菜单同一个只读查询，不消耗重置卡），结果缓存在 `/tmp/cmux-agent-activity-<uid>/codex-resets.json`；成功后最多 30 分钟问一次、失败 5 分钟后重试并保留上次结果，超过 12 小时没有成功就不再转发。`cx1` 报告追加 `rs=<张数> rx=<每张过期时间>,…`。.34+ 解析为 `codexUsage.resets`（已过期的自动扣掉）和 `resetExpiries`，面板在「本周」下面加一行「重置卡 · 最早 7号 07:00 过期 · N 张」（本机时间，一周以外带月份），一天内过期变黄、三小时内变红；更早的版本忽略这两个字段。
10. 使用重置卡（.39+）：面板「重置卡」那行有「使用」，点了出现「用掉 X 过期那张？本周已用 N%」和「确认 / 取消」（15 秒不点自动收起）。确认后面板调 socket 方法 `devbox.codex.reset.use`（无参数，只在本机 socket 上；没有进远端中继白名单），软件在面板列出的已打开会话里找一个前台是普通 `ssh` 的终端，按同样的路由、身份和选项另开一条非交互 SSH，执行 `sh -c '"$HOME/.local/bin/cmux-agent-activity-report.py" --use-reset-card'`（脚本不在就退出 127，面板提示没装）。该模式经 `codex app-server` 先 `account/rateLimits/read`，挑状态 available、过期最早的那张（没写过期时间的排最后），再 `account/rateLimitResetCredit/consume {creditId, idempotencyKey}`（Codex 自己的接口，magpie 用的是同一后端 `wham/rate-limit-reset-credits/consume`），然后重读额度、改写卡片缓存，打印一行 JSON `{outcome, expiresAt, report}`。软件把 `report`（`cx1`）直接写进那个工作区，结果作为顶层数据 `devboxCodexReset {state, at, expiresAt}` 给面板显示 2 分钟；`state` 是 `running` / `reset` / `nothingToReset` / `noCredit` / `alreadyRedeemed` / `noSession` / `unavailable` / `failed`，同一时间只跑一次，60 秒超时。

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

它会编 Apple 芯片版、用固定证书签名、给 ZIP 加 EdDSA 签名、生成 `appcast.xml`，以 `v<上游版本>-devbox.<n>` 发 Release，最后回读线上 appcast 和 ZIP 校验。版本号：显示 `<上游>-devbox.<n>`，内部 build 号 `<上游 build>.<n>`；恢复版本采用内部 build 下限；每次升级或重新编号前必须确认内部版本高于当前更新源，必要时提高下限，不能仅凭上游显示版本判断更新顺序。

构建 Mac 上的一次性准备（都在 `~/.config/cmux-devbox/`，权限 600，**不进仓库**）：
- 签名钥匙串 `~/Library/Keychains/cmux-devbox-signing.keychain-db`，内含自签名身份「cmux DevBox Code Signing」，密码在 `signing-keychain-password`，打包脚本自动解锁，无需弹框授权。
- Sparkle 私钥 `sparkle-ed25519-private.key`（对应公钥写在 `build-devbox.sh`）。

🔴 两者都要离线备份。丢了签名证书：更新后系统权限要重新授权；丢了 Sparkle 私钥：已安装的副本再也收不到更新，只能手动重装换新公钥的版本。

发布附件先进入草稿，逐个核对 GitHub 返回的已上传状态和 SHA-256，全部正确才设为最新版；上传报错但远端指纹正确时不误判失败。中断后可在同一提交、同一产物目录执行 `scripts/release-devbox.sh <n> notes.md --publish-existing`：先核版本、源码提交、应用签名和本地校验清单，再补传原始附件，不重新打包或改写更新清单。已公开版本、不同提交的草稿或指纹不匹配的附件不会自动覆盖。如果构建机自己连 GitHub 的线路传大文件会中途断开（例如系统代理把上传截断），在构建机的 `~/.config/cmux-devbox/upload-relay-host` 写一个 SSH 主机别名（或设 `CMUX_DEVBOX_UPLOAD_RELAY_HOST`）：附件改用 curl 经该主机的临时 SSH SOCKS 隧道上传，先删掉同名残件，传完关隧道；没配置时仍用 `gh release upload`。

## 长期升级约束（2026-10-19 用户确认）

后续升级以 `0.64.25-devbox.13` 为已验收基准：保留中文撑满两个字符格的字体效果、稳定的一次 SCP 直传粘图，以及 SSH 连接后提前建立的上传连接。同机相同连接配置的多个会话共用一条上传连接，不同设备互不接管；失败回退、断线重建、最后一个会话关闭后的延迟释放也必须保留。用户已在常用设备更新后确认粘图比之前更快；这是实际使用反馈，不替代各设备的定量测量。未来更新必须对照这些行为验收，不能只保留上游新功能而丢掉已确认的体验。

中文保留 `0.64.25-devbox.12` 的视觉效果：字形尽量撑满两个终端字符格，不采用上游向英文字母高度收缩的限制。以后升级不能仅凭“上游已有 CJK 修复”就撤掉现有 Ghostty 补丁；同一配置、同一屏幕下对照中文、英文和中英混排，由用户确认后才能替换。字体变小的具体运行时成因仍未完成实测归因，代码差异仅作为调查线索。

远程截图粘贴是升级的首要验收项，继续使用每张图一次 SCP 直传临时目录、插入绝对路径的方式。实机验收使用 Codex；构建成功、单元测试或另一台机器通过均不能替代用户常用设备的实际粘图验证。用户已确认安装 `0.64.25-devbox.12` 后文字样式和截图粘贴恢复正常；这是用户验收回报，不是新增自动化测量。

## 普通 SSH 图片上传连接预热

DevBox 版在本机终端出现普通前台 SSH 连接时提前建立专供上传的连接；同一台电脑上、同一目标和完整连接参数的会话共用一条，账号、密钥、端口或跳板不同则分开。使用已有 `NativeSSHConnectionBroker` 管理，观察现有终端前台 PID 后在后台读取参数，每两秒检查一次，不额外启动 `ps` 轮询。各电脑的 socket 和进程只在各自本地创建，上传目标仍是带 UUID 的独立临时文件，结果仍只交给原始粘贴请求。

只要有相关前台 SSH 会话就保留连接；最后一个会话消失后，按单调时钟等待 600 秒再关闭。重新出现会话会取消旧的释放期限。连接退出后在仍有会话时重建，失败尝试间隔至少 15 秒；退出应用时只终止本机 broker 持有的专用进程，复用现有有界进程清理。共享 socket 尚未准备好时直接走原来的 SCP；共享传输返回失败或抛出超时后只回退直连一次，取消请求不重试。禁止文件传输或禁止应用创建远程连接的策略生效时停止预热。显式指定的用户 ControlPath 和禁用 ControlMaster 不由此功能接管；不改用户 SSH 配置，不在专用连接中启动远端交互 shell、执行 RemoteCommand、LocalCommand 或建立转发。

验收必须区分 SSH 传输耗时与 Cmd+V 到 Codex 显示附件的总耗时；连接预热不等于整个粘贴流程已经达到传输耗时。双机验证要保持两台都在线，关闭其中一台的测试上传连接后，另一台仍能上传并通过内容校验。

## 升级上游

不跟 main。选定新的稳定标签后，在新标签上 cherry-pick `devbox-064` 的提交（Ghostty 子模块也要在新标签用的 Ghostty 上重放 `devbox-064` 分支的提交），解决冲突，把 `build-devbox.sh` 里的 `UPSTREAM_TAG` 改成新标签，先运行新标签实际提供的检查脚本（当前 0.64 基线使用 `bash scripts/check-pbxproj.sh`、`bash scripts/lint-pbxproj-test-wiring.sh`，不含 `verify-local.py`）和相关包测试（`CmuxRemoteSession`、`CmuxSettings`、`CmuxSettingsUI`），重新构建，再按下面的验收清单走一遍。

## 验收清单

- 普通 `ssh <主机>` → Claude Code → Command+V 截图 → `[Image #1]`，Claude 能描述图片内容。
- 同一会话连续粘 3 张图，顺序正确。
- 上传中切到别的工作区，图片不会粘到新工作区。
- 断网/远端不可达时有报错，不插入路径。
- 普通文本、多行文本粘贴不变。
- 设置、侧栏、命令面板、菜单里没有 Cloud / 登录 / 手机配对入口。
- 与官方 cmux 同时开着，两边互不影响。


## DevBox 14 剪贴板修复（2026-11-01 已发布）

保持 v0.64.25 底座、已验收的 Ghostty 字体、一次 SCP 临时目录上传和按连接配置预热不变，只移植官方 v0.65.1 的剪贴板修复及其必要依赖：普通文字由独立的小型读取程序处理，不再排在图片准备后面；完整图片程序的启动等待和准备超时分别计时；取消操作后等读取程序退出再释放剪贴板读取权。图片、文件和有损富文本仍由可终止的隔离程序处理，不把第三方剪贴板读取移回主线程。文字程序的输出大小、启动/处理时限、错误回收以及下一次读取恢复均有针对验证。

来源：[文字粘贴绕过图片等待 #18650](https://github.com/manaflow-ai/cmux/pull/18650)、[图片程序启动超时 #19164](https://github.com/manaflow-ai/cmux/pull/19164)。官方 [绝对路径修复 #18280](https://github.com/manaflow-ai/cmux/pull/18280) 已核对；当前版本的临时文件上传本来就返回绝对路径，因此保留原上传实现，不引入新的远端目录准备与清理流程。没有据此宣称历史远端上传卡住的根因已解决。

[.14 已发布](https://github.com/JayYuuuuu/cmux-devbox/releases/tag/v0.64.25-devbox.14)，自动更新入口已指向此版。自动验证、性能和发布读回结果见 [移植记录](plans/devbox-14-paste-backport.md)。本轮按用户明确要求先发布；实际设备的字体目测和远端 Codex 截图粘贴验收仍未完成，不把旧版验收套到此版。
