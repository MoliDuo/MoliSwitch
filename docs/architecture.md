# Moli Switch 架构

Moli Switch 是一个 macOS 菜单栏工具：前台应用、终端里运行的程序或当前输入框变了，就切到为它设定的输入法。用户能看到的行为见 [README](../README.md)。

## 模块

| 目录 | 职责 |
|---|---|
| `Sources/MoliSwitchCore` | 不依赖 AppKit 的逻辑：应用规则、终端程序规则、输入框规则及其 JSON 存储；“该用哪个输入法”的判定；斜杠命令和按住 Shift 的状态机；使用日志和根据日志给出的规则建议。全部有单元测试。 |
| `Sources/MoliSwitchApp` | 和系统打交道的部分：运行时（`AppRuntime`）、输入法读取和切换（Text Input Sources）、用辅助功能读当前输入框、读终端里的程序、全局按键监听、Sparkle 更新、从 AutoInputSwitcher 迁移、单实例、登录时打开，以及主窗口（`Views/`，SwiftUI）。 |
| `Sources/MoliSwitch` | 可执行入口，只调用 App 模块。 |
| `Sources/MoliSwitchCoreChecks` | 不依赖 XCTest 的核心自检，`Scripts/check.sh` 里先于单元测试运行。 |

## 数据流

1. **前台应用变化**：`NSWorkspace` 通知 → 运行时查应用规则（没有单独设置就用默认）→ 解析成具体输入法（“中文”“英文”是角色，按页面顶部的设置换成具体输入法）→ 切换后读回确认，没切过去就在窗口顶部提示。
2. **终端程序**：前台是“终端”或 iTerm2 时，在后台串行队列里用 Apple Events 读当前标签页的 tty，再用 `sysctl` 找这个 tty 前台的进程（tmux 例外，要问 tmux 本身），按终端程序规则切换。
3. **输入框**：用辅助功能读当前聚焦的元素和它的标识（浏览器地址栏、记住的输入框），有规则就优先于应用规则。
4. **打字时切换**：会话级事件监听（`CGEvent.tapCreate`）看到每次按键：
   - 斜杠命令：在勾选的 App 里，输入框开头打 `/` 时切到英文，命令结束（回车、Esc、删掉 `/`、离开输入框）后切回。
   - 按住 Shift：用中文输入法时按住 Shift 先把按键扣住，切到英文后再按原样打出去，松开后切回；超时没等到松开也会打出去，不会吞字。
5. **使用日志**：每次切换、按键类别、诊断信息写成按天分文件的 JSON Lines（`~/Library/Application Support/MoliSwitch/usage/`，保留 30 天，按新加坡时间分天），分析后在“优化建议”页给出规则建议。

规则和设置都只存在本机 `~/Library/Application Support/MoliSwitch/`。

## 关键决定

| 决定 | 原因 |
|---|---|
| Core 不依赖 AppKit | 判定逻辑和状态机能在没有窗口、没有权限的环境里测试；系统相关的东西集中在 App 模块，换实现时不动规则。 |
| “中文”“英文”是角色而不是具体输入法 | 换了中文输入法只改一处，所有规则跟着变。 |
| 规则文件读不出来时不动原文件、暂停编辑 | 宁可不能改，也不能用空规则覆盖用户的配置。设置字段只加不删（MoliSpec 009）。 |
| 终端程序用 Apple Events + `sysctl`，不启动 `ps` | 每次按键都可能触发检查，起进程太慢；Apple Events 有时要一秒，所以放在后台队列。 |
| 按住 Shift 先扣住按键再补发 | 先切输入法再让按键过去，才能保证这个字母是英文；补发的事件带标记，监听器放行，不会循环。 |
| 更新用 Sparkle 2 | macOS 上成熟的应用内更新，支持 Ed25519 签名和签名的更新清单（MoliSpec 007）。更新源固定为 `releases/latest/download/appcast.xml`，已安装的版本都从这里读，不能改名。 |
| 用固定的自签名证书签名，不用 ad-hoc | ad-hoc 签名每个版本都不同，系统会把更新后的版本当成新应用，辅助功能和自动化授权失效。固定证书让授权跨版本保留。没有 Apple 开发者账号，所以没有公证，首次打开要手动放行。 |
| Bundle ID 保持 `com.moli.MoliSwitch` | 改成规范的 `com.moliduo.switch` 会让已安装的版本收不到更新、权限全部重授。记为 `moli.yaml` 里的例外，等下次本来就要重装时再迁移。 |
| 在磁盘映像或 App Translocation 路径里运行时拒绝更新 | 从这些位置替换应用会失败或装到看不见的地方；先提示移到“应用程序”。 |
| 通用二进制（arm64 + x86_64） | 最低支持 macOS 14，仍有 Intel Mac 在用。 |
| 时间按新加坡时间显示和分天 | MoliSpec 013：给人看的时间和按天切分都用 `Asia/Singapore`，换机器或出差时日志不乱。诊断里另外记录系统时区本身。 |

## 发布

版本只写在 `VERSION`，`CFBundleVersion` = X×1000000 + Y×1000 + Z（`Scripts/common.sh`）。推 `vX.Y.Z` 标签后 `release.yml` 用组织密钥签名应用（`CODESIGN_P12_*`）和更新清单（`SPARKLE_PRIVATE_KEY`），发布 `MoliSwitch_X.Y.Z_macos_universal.{dmg,zip}`、`appcast.xml` 和 `SHA256SUMS`，再核对线上清单。Sparkle 密钥由组织里所有 Mac 应用共用；私钥丢失后已发布的版本无法再自动更新。

## 第三方依赖

- [Sparkle](https://sparkle-project.org)（MIT），通过 SwiftPM 引入。
