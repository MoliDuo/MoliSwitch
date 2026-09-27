# MoliSwitch

MoliSwitch 是一个原生 macOS 小工具：根据当前前台应用自动切换键盘输入法。它是 Moli 系列的一员，以前叫 AutoInputSwitcher。

- 扫描已安装的应用，为每个应用保存一条输入法规则。
- 在“通用”里指定一次“中文 / 英文”分别用哪个输入法，每个应用的规则只需选“默认”“中文”“英文”或“不切换”。
- 可设一个默认输入法：没单独设规则的应用成为前台时都切到它。
- 在“终端”和 iTerm2 里还能按正在运行的程序切换：比如进入 claude、codex 用中文，vim 和 shell 用英文。
- 同一个 App 里还能按输入框切换：浏览器地址栏默认用英文，也可以记住某个输入框（比如微信的搜索框）单独用一个输入法。
- 规则只保存在本机（`~/Library/Application Support/MoliSwitch/`）。
- 关闭窗口后继续在后台运行；不显示 Dock 图标（`LSUIElement`），可选择显示菜单栏图标。
- 可设置为登录时打开。
- 内置 Sparkle 自动更新，每小时检查一次新版本。

## 系统要求

- macOS 14 或更高版本
- 开发需要 Swift 6 工具链（Command Line Tools 或 Xcode）

发布包为 arm64 + x86_64 通用二进制。

## 使用

### 打开与退出

- 从 Finder、Spotlight 或启动台打开时显示主窗口；已经在运行时再打开一次，也会把窗口带到前面。
- 登录时自动打开的那一次不显示窗口，只在后台运行。
- 关闭窗口（⌘W）后 MoliSwitch 继续运行。要退出，在窗口里按 ⌘Q，或点菜单栏图标 › 退出 MoliSwitch。
- 菜单栏图标的菜单里有：记住当前输入框、打开 MoliSwitch…（⌘,）、检查更新…、关于、退出。
- 在“通用”里关掉菜单栏图标后，再次打开 MoliSwitch 即可回到主窗口。

主窗口左侧是四个页面：应用、终端程序、输入框、通用。

### 应用

页面顶部的“默认输入法”作用于所有没有单独设置的应用，初始为“不切换”。下面的表格里，每个已安装的应用占一行：

- “默认（…）”：跟随默认输入法，括号里显示默认现在是什么。
- “不切换”：该应用始终不做自动切换，默认输入法也不会作用于它。
- “中文”或“英文”：切到“通用”里设置的中文或英文输入法。以后换了中文输入法，只要改一处，所有“中文”规则都会跟着变。
- 下拉框下半部分列出其他输入法（比如日文），也可以直接选一个具体的输入法。
- 规则里保存的输入法在当前系统上不可用时，选择器会保留一项“不可用：{已保存名称}”，规则不会被自动删除或改写，请手动改选。
- 规则指向的应用已经卸载时，该行标记“未找到应用”，仍可修改规则。

工具栏里有搜索框、“全部 / 已设置 / 未设置”筛选和重新扫描应用与输入法的按钮。

### 中文和英文输入法

“通用”里的“输入法”一节指定这两个角色，默认都是“自动识别”：

- 中文：不是键盘布局的输入法，优先系统自带的简体 / 繁体中文输入法（如“双拼”）；没有系统自带的才用第三方的（如微信键盘、搜狗）。装了多个中文输入法时建议手动指定。
- 英文：第一个键盘布局（如 U.S. 或 ABC）。

第三方输入法要先在 系统设置 › 键盘 › 输入法 中添加，之后才会出现在列表里。每次切换后会读回当前输入法确认，系统没有切过去时窗口顶部会提示。

系统自带中文输入法开启“用大小写键切换到/离开 U.S.（或 ABC）”时，按大小写键其实就是在中文输入法和 U.S. 之间切换；所以把“英文”设为 U.S.，规则选“英文”的效果和手动按一下大小写键相同。

已有规则如果直接选的是当前的中文或英文输入法，会显示为“中文”或“英文”；之后改掉这个角色时，这些规则会一起跟过去。

### 终端程序

在“终端程序”页可以给命令行程序单独设规则，比如 `claude`、`codex` 用“中文”，`vim`、`nvim` 用“英文”。“终端”和 iTerm2 共用这些规则，保存在 `command-rules.json`。

- 前台是“终端”或 iTerm2 时，每 0.5 秒看一次当前标签页里正在运行的程序：命中规则就切到对应输入法；没有命中（比如回到了 shell）就用这个终端 App 自己的规则。
- 只在“该用哪条规则”变化时切换，比如启动或退出程序、换标签页、从别的 App 切回终端。停在同一个程序里手动切过的输入法不会被改回去。
- 程序名不区分大小写，依次比对：解释器运行的脚本名（如 `node …/bin/codex` 里的 `codex`）、启动时的名字（argv[0]）、可执行文件名、进程名。
- 刚在终端里跑过、还没有规则的程序，页面上会出现“添加刚才在终端中运行的…”。
- tmux 里会识别当前窗格正在运行的程序。
- ssh 只能看到 `ssh` 本身，看不到远程机器上运行的程序，所以只能给 `ssh` 整体设一条规则。
- 读取当前标签页需要“自动化”权限，第一次用到时系统会询问。拒绝后可以在 系统设置 › 隐私与安全性 › 自动化 里重新打开。
- 没有设任何程序规则、或者关掉了开关时，不会读取终端，也不会请求权限。

### 输入框

“输入框”页需要“辅助功能”权限来读取当前聚焦的是哪个输入框；只读取输入框的类型、标识和说明文字，**不读取输入的内容**。

- 浏览器地址栏：默认打开，点进地址栏时切到“英文”，离开后按下面的规则切回。可以关掉，或改成别的输入法。支持 Safari、Chrome、Edge、Brave、Vivaldi、Opera、Chromium 和 Firefox。
- 记住某个输入框：
  1. 在目标 App 里点一下要记住的输入框，手动切到想用的输入法。
  2. 点菜单栏图标，选“记住当前输入框（App · 输入法）”。
  3. 以后焦点进入这个输入框就切到这个输入法。再记一次同一个输入框会覆盖原来的输入法。
- 记住的输入框保存在 `field-rules.json`，可以在“输入框”页改名、改输入法或删除。
- 优先级：终端程序规则 → 输入框规则（含地址栏）→ 应用规则 → 默认输入法。
- 离开输入框时，如果该 App 有自己的规则就按 App 规则切；没有的话切回进入输入框前的输入法（在输入框里手动切过的话就保持不动）。
- 和终端程序一样，只在“该用哪条规则”变化时切换。
- 只有记住了输入框的 App，或者打开了地址栏开关时的浏览器，才会被监听；没有授权时这一功能不生效，其余照常。
- 识别输入框靠的是 App 暴露的辅助功能信息：有的 App（部分 Electron 应用、网页里没有 id 的输入框）结构会随内容变化，可能认不准，这种情况只能退回应用规则。

### 规则文件出错时

规则文件读取失败时，MoliSwitch 会暂停规则编辑并在窗口顶部持续提示，原文件不会被动过；可以点“重新读取”，或点“在 Finder 中显示”手动处理。保存失败时修改不会生效，界面保留修改前的状态。

## 安装

从 [Releases](https://github.com/MoliDuo/MoliSwitch/releases) 下载 `MoliSwitch-macOS.dmg`，打开后把 `MoliSwitch.app` 拖进“应用程序”。

首次打开时系统会拦截：发布包使用自签名证书、没有做 Apple 公证，需要在 系统设置 › 隐私与安全性 里选择“仍要打开”。

请把应用安装到“应用程序”文件夹再使用更新功能。如果直接从未挂载的只读磁盘映像里运行，应用会提示你先安装到“应用程序”。

### 从 AutoInputSwitcher 升级

MoliSwitch 换了名字和 Bundle ID，系统会把它当成一个新应用：

- **需要手动安装一次。** AutoInputSwitcher 的自动更新不会升级到 MoliSwitch，请按上面的步骤下载安装。
- **规则和设置会自动带过来。** MoliSwitch 第一次打开时，会把 AutoInputSwitcher 的应用规则、终端程序规则、输入框规则和各项设置复制过来（旧文件保留不动）。
- **退出并删除旧版。** 两个同时运行会重复切换输入法。MoliSwitch 发现旧版在运行时会提示退出它；之后请在 系统设置 › 通用 › 登录项 里移除 AutoInputSwitcher，再把 `AutoInputSwitcher.app` 移到废纸篓。
- **重新授权。** 辅助功能和自动化权限要给 MoliSwitch 重新授予一次，“登录时打开”也要在“通用”里重新打开。

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
https://github.com/MoliDuo/MoliSwitch/releases/latest/download/appcast.xml
```

清单内部指向更新包的下载地址始终是具体版本 tag（形如 `build-<run>-<attempt>`），不会使用 `latest`，避免清单与安装包版本错配。应用校验 Ed25519 签名，并要求清单本身已签名（`SURequireSignedFeed = true`）。

## 本地开发

```bash
# 一次性完整校验：核心检查 + 单元测试 + 打包 + 产物校验
./Scripts/test.sh

# 只构建应用 bundle。本地试用时把 BUILD_NUMBER 设大，
# 否则 Sparkle 会认为有新版本，把测试包替换成正式版
BUILD_NUMBER=9999 ./Scripts/build-app.sh
open .build/MoliSwitch.app

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
| `SIGN_IDENTITY` | `-` | 签名身份，默认 ad-hoc；也可以填证书 SHA-1 指纹 |
| `SIGN_KEYCHAIN` | 空 | 证书所在的钥匙串，传给 `codesign --keychain` |
| `FEED_URL` | 仓库 Releases 的 appcast 地址 | 覆盖 `SUFeedURL` |

## 打包

```bash
./Scripts/package-release.sh   # 产出 ZIP、DMG、checksums.txt、build-manifest.json
./Scripts/verify-package.sh    # 校验产物
```

产物写入 `.build/dist`：

```text
.build/dist/MoliSwitch-macOS.dmg   # 手动安装用
.build/dist/MoliSwitch-macOS.zip   # Sparkle 更新用，ditto 打包以保留 bundle 结构
.build/dist/checksums.txt
.build/dist/build-manifest.json
```

`verify-package.sh` 会检查：双架构、最低系统版本、Sparkle.framework 与辅助进程是否完整、签名是否有效、bundle 内是否残留指向 `.build` 的绝对加载路径、ZIP 与 DMG 是否包含同一份应用。设置 `REQUIRE_SIGNING_CERTIFICATE=1` 时还会要求应用、Sparkle.framework 及其辅助进程都由 `Config/CodeSigningCertificate.txt` 记录的证书签名（CI 发布构建即如此）。

## 一次性生成 Sparkle 密钥

更新信任只依赖一对 Ed25519 密钥：公钥随应用发布，私钥只用于签名更新包与更新清单。

```bash
# SPARKLE_TOOLS_DIR 指向含 bin/generate_keys 的 Sparkle 工具目录
SPARKLE_TOOLS_DIR=.build/artifacts/sparkle/Sparkle/bin \
  ./Scripts/setup-sparkle-keys.sh "$HOME/MoliSwitch-sparkle-private-key.txt"
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

## 一次性生成代码签名证书

ad-hoc 签名的应用每个版本签名都不同，系统会把更新后的版本当成新应用，辅助功能、自动化授权随之失效。正式版因此用一张固定的自签名证书签名：签名要求变成“Bundle ID + 证书”，跨版本不变，授权得以保留。它不被 Gatekeeper 信任，首次安装仍需“仍要打开”。

```bash
./Scripts/setup-signing-certificate.sh "$HOME/MoliSwitch-codesign"
```

脚本会：

1. 生成 10 年有效的代码签名证书，连同私钥导出为 `.p12`（随机口令，口令写在同目录的 `.password` 文件里）；
2. 把证书 SHA-1 指纹写入 `Config/CodeSigningCertificate.txt`。

然后：

1. 在仓库的 Actions secrets 里新增 `CODESIGN_P12_BASE64`（`base64 -i MoliSwitch-codesign.p12` 的输出）和 `CODESIGN_P12_PASSWORD`（口令）；
2. 把 `.p12` 与口令复制到离线介质另行备份，然后从本机删除；
3. 提交 `Config/CodeSigningCertificate.txt`。

注意：

- 证书不需要加入本机或 CI 的钥匙串信任；CI 把它导入一个临时钥匙串，按指纹签名，结束后删除。
- 换证书会让所有用户重新授权一次辅助功能与自动化权限；证书丢失后只能换新证书。Sparkle 更新不受影响，它只要求 Ed25519 签名有效。

## CI/CD

两个工作流分工明确：构建可取消，发布不可中断。

**`.github/workflows/release.yml`（Build and Verify）**

- 触发：PR、`main` 上的 push、手动触发。权限只有 `contents: read`。
- 同一分支上的新构建会取消旧构建。
- `checks`：`swift run MoliSwitchCoreChecks` 与 `swift test`，**失败即阻断打包**（没有 `continue-on-error`）。
- `build`：下载固定版本的 Sparkle 工具（带 sha256 校验）；非 PR 构建把 `CODESIGN_P12_BASE64` 导入临时钥匙串并用固定证书签名（缺少 secret 直接失败），PR 构建拿不到 secrets，仍用 ad-hoc 签名。然后打包出 ZIP、DMG、`checksums.txt`、`build-manifest.json`，由 `verify-package.sh` 校验（非 PR 构建要求证书签名），最后删除临时钥匙串并上传为构建产物。
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

- 发布包使用自签名证书，未使用 Developer ID，也未做 Apple 公证：首次安装需要手动在“隐私与安全性”里允许。
- Ed25519 更新签名保证的是“更新来自持有私钥的发布者”，不能替代 Gatekeeper 信任。
- 暂不支持增量更新、多发布通道和自建更新服务器。
- 按程序切换只支持“终端”和 iTerm2，其他终端（Ghostty、WezTerm、Warp 等）只按 App 规则切换。
- 按输入框切换依赖辅助功能权限。正式版用固定证书签名，授权在更新后保留。
- 从 AutoInputSwitcher 改名为 MoliSwitch 后 Bundle ID 变了，旧版无法自动更新过来，权限也要重新授予，见“从 AutoInputSwitcher 升级”。

## 项目结构

```text
Sources/MoliSwitchCore/        规则、配置存储、列表过滤（不依赖 AppKit / Sparkle）
Sources/MoliSwitchApp/         运行时、系统集成、更新控制器、旧版数据迁移
Sources/MoliSwitchApp/Views/   主窗口界面（SwiftUI）
Sources/MoliSwitch/            可执行入口
Sources/MoliSwitchCoreChecks/  核心逻辑自检
Tests/                         单元测试
Scripts/                       构建、打包、校验、appcast、密钥脚本
Config/SparklePublicKey.txt    更新公钥（可公开、可提交）
```

