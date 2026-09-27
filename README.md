# AutoInputSwitcher

AutoInputSwitcher 是一个原生 macOS 小工具：根据当前前台应用自动切换键盘输入法。

它的行为刻意保持简单：

- 扫描已安装的应用，为每个应用保存一条输入法规则。
- 在设置里指定一次“中文 / 英文 / 语音”分别用哪个输入法，每个应用的规则只需选“默认”“中文”“英文”或“不切换”。
- 可设一个默认输入法：没单独设规则的应用成为前台时都切到它。
- 规则只保存在本机（`~/Library/Application Support/AutoInputSwitcher/rules.json`）。
- 关闭窗口后继续在后台运行；可从 Finder、Spotlight、Launchpad 或菜单栏图标重新打开。
- 可选择显示菜单栏图标；不显示 Dock 图标（`LSUIElement`）。
- 可设置为登录时启动。
- 统计“实际发生切换”的次数。
- 在“终端”和 iTerm2 里还能按正在运行的程序切换：比如进入 claude、codex 用中文，vim 和 shell 用英文。
- 同一个 App 里还能按输入框切换：浏览器地址栏默认用英文，也可以记住某个输入框（比如微信的搜索框）单独用一个输入法。
- 可选：用豆包输入法做完一次语音输入后，自动切回语音输入前正在用的输入法。
- 内置 Sparkle 自动更新，每小时检查一次新版本。

## 系统要求

- macOS 14 或更高版本
- 开发需要 Swift 6 工具链（Command Line Tools 或 Xcode）

发布包为 arm64 + x86_64 通用二进制。

## 使用

打开主窗口后，每个已安装的应用在表格里占一行：

- 选择“默认（…）”：该应用没有自己的规则，跟随齿轮按钮里的“默认输入法”；括号里显示默认现在是什么。默认输入法初始为“不切换”，也就是和以前一样不动这些应用。
- 选择“不切换”：该应用始终不做自动切换，默认输入法也不会作用于它。
- 选择“中文”或“英文”：该应用成为前台时，切到齿轮按钮里设置的中文或英文输入法。以后换了中文输入法，只要改一处设置，所有“中文”规则都会跟着变。
- 下拉框下半部分列出其他输入法（比如日文），也可以直接选一个具体的输入法。
- 规则里保存的输入法在当前系统上不可用时，选择器仍会保留一项“不可用：{已保存名称}”，规则不会被自动删除或改写。请手动改选一个可用输入法。
- 规则指向的应用已经卸载时，该行会标记“未找到应用”，仍可修改或删除规则。
- “全部 / 已配置 / 未配置”用于筛选列表，“未配置”只显示扫描到且还没有规则的应用。
- 右上角的刷新按钮会重新扫描应用和输入法；齿轮按钮里是开机自启、菜单栏图标、默认输入法、中文 / 英文 / 语音输入法、语音输入后切回、检查更新和退出。
- 窗口底部显示当前状态、已配置的应用数和本次运行以来的切换次数。

### 语音输入后切回原输入法

豆包输入法的语音唤醒键（如 option+command）会先把系统输入法切到豆包再录音，文字上屏后输入法仍停在豆包。主窗口齿轮按钮里可以打开“语音输入后切回原输入法”：

- 一次语音输入结束（麦克风不再被占用、豆包的识别浮窗消失后再等约 0.3 秒）后，自动切回切到豆包之前的输入法；如果浮窗一直检测不到消失，麦克风停止 8 秒后也会切回。
- 只是手动切到豆包打字、没有用麦克风时，不会切回。
- 等待切回期间如果手动切到别的输入法，或规则切换了输入法，本次不再切回。
- 语音输入法默认自动识别名称含“豆包”或 ID 含 `doubao` 的输入法，也可以在“输入法”一节手动指定。
- 只读取“麦克风是否被占用”和窗口的归属与位置，不录音、不读取窗口内容，不需要麦克风或屏幕录制权限。
- 切回也计入“已切换”次数。
- 功能打开时，App 规则的下拉框里不再列出语音输入法（已经设成它的旧规则仍然保留）。
- 系统自带中文输入法开启“用大小写键切换到/离开 U.S.（或 ABC）”时，按大小写键其实就是在中文输入法和 U.S. 之间切换；所以把“英文”设为 U.S.，规则选“英文”的效果和手动按一下大小写键相同。

### 中文、英文、语音输入法

齿轮按钮里的“输入法”一节可以指定这三个角色，默认都是“自动识别”：

- 中文：既不是键盘布局、也不是语音输入法的输入法，优先系统自带的简体 / 繁体中文输入法（如“双拼”）；没有系统自带的才用第三方的（如微信键盘、搜狗）。装了多个中文输入法时建议手动指定。
- 英文：第一个键盘布局（如 U.S. 或 ABC）。
- 语音：名称含“豆包”或 ID 含 `doubao` 的输入法。

第三方输入法（微信键盘、搜狗、手心等）要先在 系统设置 › 键盘 › 输入法 中添加，之后才会出现在列表里。每次切换后会读回当前输入法确认，系统没有切过去时状态栏会提示。

已有规则如果直接选的是当前的中文或英文输入法，会显示为“中文”或“英文”；之后在设置里改掉这个角色时，这些规则会一起跟过去。

### 终端里按程序切换

主窗口工具栏的终端按钮里可以给命令行程序单独设规则，比如 `claude`、`codex` 用“中文”，`vim`、`nvim` 用“英文”。规则保存在同目录的 `command-rules.json`，“终端”和 iTerm2 共用。

- 前台是“终端”或 iTerm2 时，每 0.5 秒看一次当前标签页里正在运行的程序：
  - 命中规则就切到对应输入法。
  - 没有命中（比如回到了 shell）就用这个终端 App 自己的规则。
- 只在“该用哪条规则”变化时切换，比如启动或退出程序、换标签页、从别的 App 切回终端。停在同一个程序里手动按大小写键切过的输入法不会被改回去。
- 正在用语音输入法时先不切，等它切回后再按当前程序切换，不会打断语音识别。
- 程序名不区分大小写，会依次比对：
  - 解释器运行的脚本名，比如 `node …/bin/codex` 里的 `codex`
  - 启动时的名字（argv[0]）
  - 可执行文件名
  - 进程名

  刚在终端里跑过、还没有规则的程序，会显示一个“添加刚才在终端里运行的…”快捷按钮。
- tmux 里会识别当前窗格正在运行的程序。
- ssh 只能看到 `ssh` 本身，远程机器上运行的程序看不到，所以只能给 `ssh` 整体设一条规则。
- 读取当前标签页需要“自动化”权限：第一次在终端里用到规则时系统会询问。拒绝后可以在“系统设置 → 隐私与安全性 → 自动化”里重新打开。发布包是 ad-hoc 签名，每次更新后系统可能会再询问一次。
- 没有设任何程序规则、或者关掉了开关时，不会读取终端，也不会请求权限。

### 按输入框切换

主窗口工具栏的“按输入框切换”按钮里管理这一功能。它需要“辅助功能”权限来读取当前聚焦的是哪个输入框；只读取输入框的类型、标识和说明文字，**不读取输入的内容**。

- 浏览器地址栏：默认打开，点进地址栏时切到“英文”，离开地址栏后按下面的规则切回。可以关掉，或改成别的输入法。支持 Safari、Chrome、Edge、Brave、Vivaldi、Opera、Chromium 和 Firefox。
- 自定义输入框：
  1. 在目标 App 里点一下要记住的输入框，手动切到想用的输入法。
  2. 点菜单栏图标，选“记住当前输入框：<App> 使用 <输入法>”。
  3. 以后焦点进入这个输入框就切到这个输入法。再记一次同一个输入框会覆盖原来的输入法。
- 规则保存在同目录的 `field-rules.json`，在管理窗口里可以改名、改输入法或删除。
- 优先级：终端里的程序规则 → 输入框规则（含地址栏）→ App 规则 → 默认输入法。
- 离开输入框时，如果该 App 有自己的规则就按 App 规则切；没有的话切回进入输入框前的输入法（在输入框里手动切过输入法的话就保持不动）。
- 和终端规则一样，只在“该用哪条规则”变化时切换；停在同一个输入框里手动切过的输入法不会被改回去；正在用语音输入法时先不切。
- 只有设置了输入框规则的 App，或者打开了地址栏开关时的浏览器，才会被监听；没有授权时这一功能不生效，其余照常。
- 授权方式：管理窗口里点“授权…”，或在“系统设置 → 隐私与安全性 → 辅助功能”里打开 AutoInputSwitcher。发布包是 ad-hoc 签名，每次更新后可能需要在这里重新打开一次（先关再开）。
- 识别输入框靠的是 App 暴露的辅助功能信息：有的 App（部分 Electron 应用、网页里没有 id 的输入框）结构会随内容变化，可能认不准，这种情况只能退回 App 规则。

排查问题时可以查看日志：

```bash
log stream --level debug --predicate 'subsystem == "com.local.AutoInputSwitcher" AND category == "voice"'
```

主窗口齿轮按钮里提供“检查更新…”，用于手动检查更新；菜单栏菜单里也有同一项。

规则文件读取失败时，应用会暂停规则编辑并在界面上持续提示，原文件不会被动过；可以点“重新读取”，或用“在 Finder 中显示规则文件”手动处理。保存失败时修改不会生效，界面保留修改前的状态。

## 安装

从 [Releases](https://github.com/xiangyumou/AutoInputSwitcher/releases) 下载 `AutoInputSwitcher-macOS.dmg`，打开后把 `AutoInputSwitcher.app` 拖进“应用程序”。

首次打开时系统会拦截：因为发布包使用 ad-hoc 签名、没有做 Apple 公证，需要在“系统设置 → 隐私与安全性”里选择“仍要打开”。

> **重要：** 首个带自动更新功能的版本必须手动安装一次。之前的版本没有更新器，无法自己升级到这一版；此后新版本才会自动提示。

请把应用安装到“应用程序”文件夹再使用更新功能。如果直接从未挂载的只读磁盘映像里运行，应用会提示你先安装到“应用程序”。

## 自动更新

更新由 [Sparkle 2](https://sparkle-project.org) 完成，行为是：

- 默认每小时检查一次（`SUScheduledCheckInterval = 3600`）。
- 发现新版本后先提示，用户确认后才下载、安装并重启。
- 不会在后台静默替换：`SUAutomaticallyUpdate` 与 `SUAllowsAutomaticUpdates` 均为 `false`。
- 后台检查遇到网络错误不会打扰用户；手动“检查更新…”会明确显示“已是最新”或失败原因。
- 更新提示不受主窗口隐藏或菜单栏图标关闭的影响。
- 更新退出前会清理运行时并释放单实例锁，重启后只保留一个实例。

更新清单地址为：

```text
https://github.com/xiangyumou/AutoInputSwitcher/releases/latest/download/appcast.xml
```

清单内部指向更新包的下载地址始终是具体版本 tag（形如 `build-<run>-<attempt>`），不会使用 `latest`，避免清单与安装包版本错配。应用校验 Ed25519 签名，并要求清单本身已签名（`SURequireSignedFeed = true`）。

## 本地开发

```bash
# 一次性完整校验：核心检查 + 单元测试 + 打包 + 产物校验
./Scripts/test.sh

# 只构建应用 bundle
./Scripts/build-app.sh
open .build/AutoInputSwitcher.app

# 单独运行测试
swift test
```

`Scripts/build-app.sh` 的环境变量：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `VERSION` | `0.2.0` | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | `1` | `CFBundleVersion` |
| `CONFIGURATION` | `release` | Swift 构建配置 |
| `UNIVERSAL` | `1` | `1` 构建 arm64 + x86_64，`0` 只构建本机架构 |
| `SIGN_IDENTITY` | `-` | 签名身份（ad-hoc） |
| `FEED_URL` | 仓库 Releases 的 appcast 地址 | 覆盖 `SUFeedURL` |

## 打包

```bash
./Scripts/package-release.sh   # 产出 ZIP、DMG、checksums.txt、build-manifest.json
./Scripts/verify-package.sh    # 校验产物
```

产物写入 `.build/dist`：

```text
.build/dist/AutoInputSwitcher-macOS.dmg   # 手动安装用
.build/dist/AutoInputSwitcher-macOS.zip   # Sparkle 更新用，ditto 打包以保留 bundle 结构
.build/dist/checksums.txt
.build/dist/build-manifest.json
```

`verify-package.sh` 会检查：双架构、最低系统版本、Sparkle.framework 与辅助进程是否完整、签名是否有效、bundle 内是否残留指向 `.build` 的绝对加载路径、ZIP 与 DMG 是否包含同一份应用。

## 一次性生成 Sparkle 密钥

更新信任只依赖一对 Ed25519 密钥：公钥随应用发布，私钥只用于签名更新包与更新清单。

```bash
# SPARKLE_TOOLS_DIR 指向含 bin/generate_keys 的 Sparkle 工具目录
SPARKLE_TOOLS_DIR=.build/artifacts/sparkle/Sparkle/bin \
  ./Scripts/setup-sparkle-keys.sh "$HOME/AutoInputSwitcher-sparkle-private-key.txt"
```

脚本会：

1. 生成（或复用）密钥对，并把公钥写入 `Config/SparklePublicKey.txt`；
2. 把私钥导出到你指定的新路径（权限 `600`）。

然后：

1. 在仓库的 Actions secrets 里新增 `SPARKLE_PRIVATE_KEY`，内容就是导出的私钥全文；
2. 把私钥复制到离线介质另行备份，然后从本机删除；
3. 提交 `Config/SparklePublicKey.txt`。

注意：

- 不要在 CI 里生成新密钥；每次发布都必须用同一把密钥。私钥不进入源码、日志和构建产物。
- 私钥丢失后，已发布的版本无法再自动更新，用户只能重新手动安装。
- `Config/SparklePublicKey.txt` 仍是占位值时，`build-app.sh` 会拒绝打包：无法验证更新的安装包不该发布。

## CI/CD

两个工作流分工明确：构建可取消，发布不可中断。

**`.github/workflows/release.yml`（Build and Verify）**

- 触发：PR、`main` 上的 push、手动触发。权限只有 `contents: read`。
- 同一分支上的新构建会取消旧构建。
- `checks`：`swift run AutoInputSwitcherCoreChecks` 与 `swift test`，**失败即阻断打包**（没有 `continue-on-error`）。
- `build`：下载固定版本的 Sparkle 工具（带 sha256 校验），打包出 ZIP、DMG、`checksums.txt`、`build-manifest.json`，然后由 `verify-package.sh` 校验，最后上传为构建产物。
- 只有 `main` 上的 push 或 `main` 上的手动构建才具备发布资格；PR 只做验证。

**`.github/workflows/publish.yml`（Publish Release）**

- 触发：`workflow_run`，即上游 Build and Verify 在 `main` 上完成后。权限 `contents: write`。
- 只接受结论为成功、来源是本仓库、并且不是 PR 的上游运行。
- 按准确的 `workflow_run.id` 下载产物，不使用“最新构建”之类的模糊匹配。
- 发布串行执行（`cancel-in-progress: false`）。签名只运行受信的 `main` 工作流代码，不执行产物里的任何脚本。
- 校验清单记录的 tag、提交与上游一致；上游提交必须仍是 `main` 的 HEAD；版本必须高于当前正式版。不满足则跳过这次过期构建。
- 缺少 `SPARKLE_PRIVATE_KEY` 或签名校验失败会直接失败，不会产出正式版。
- 流程：生成并签名 `appcast.xml` → 创建草稿 Release → 上传 ZIP、DMG、appcast、校验和 → 公开前再确认提交仍然是最新 → 公开并标记 latest → 验证公开清单与附件可下载。
- 失败会保留未公开草稿以便诊断，同一构建重跑会复用草稿继续上传。已发布的版本不会被删除、覆盖或重写 tag。

**版本编号**统一取上游 Build and Verify 的编号：

| 名称 | 形式 |
|---|---|
| 显示版本 | `0.2.<run_number>` |
| `CFBundleVersion` | `<run_number>.<run_attempt>` |
| tag | `build-<run_number>-<run_attempt>` |

同一构建重跑时版本号递增；发布工作流自身的编号不参与版本计算。“只发布最新成功版本”指取消和跳过尚未发布的过期构建，已经公开的版本会保留。

## 已知限制

- 发布包使用 ad-hoc 签名，未使用 Developer ID，也未做 Apple 公证：首次安装需要手动在“隐私与安全性”里允许。
- Ed25519 更新签名保证的是“更新来自持有私钥的发布者”，不能替代 Gatekeeper 信任。
- 暂不支持增量更新、多发布通道和自建更新服务器。
- 按程序切换只支持“终端”和 iTerm2，其他终端（Ghostty、WezTerm、Warp 等）只按 App 规则切换。
- 按输入框切换依赖辅助功能权限；ad-hoc 签名的新版本可能需要重新授权。

## 项目结构

```text
Sources/AutoInputSwitcherCore/       规则、配置存储、列表过滤（不依赖 AppKit / Sparkle）
Sources/AutoInputSwitcherApp/        运行时、界面、系统集成、更新控制器
Sources/AutoInputSwitcher/           可执行入口
Sources/AutoInputSwitcherCoreChecks/ 核心逻辑自检
Tests/                               单元测试
Scripts/                             构建、打包、校验、appcast、密钥脚本
Config/SparklePublicKey.txt          更新公钥（可公开、可提交）
```

