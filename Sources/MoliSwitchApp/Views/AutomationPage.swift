import AppKit
import MoliSwitchCore
import SwiftUI

/// Switching that follows what happens inside an application: Shift, slash
/// commands, programs in the terminal and text fields. Which applications use
/// Shift and slash commands is set in the application table.
struct AutomationPage: View {
    @ObservedObject var runtime: AppRuntime
    @AppStorage("selectedSidebarItem") private var sidebarSelection: SidebarItem = .automation
    @State private var newCommand = ""

    var body: some View {
        Form {
            notices
            shiftSection
            slashCommandSection
            terminalSections
            fieldSections
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may come back from System Settings having changed something.
            refresh()
        }
    }

    private func refresh() {
        runtime.refreshAccessibilityTrust()
        runtime.refreshInputSourceIndicator()
    }

    // MARK: - Notices

    @ViewBuilder
    private var notices: some View {
        if !runtime.accessibilityTrusted {
            Section {
                NoticeRow(text: "需要“辅助功能”权限才能读取按键、识别光标所在的输入框。") {
                    Button("打开系统设置…") {
                        runtime.requestAccessibilityTrust()
                        runtime.openAccessibilitySystemSettings()
                    }
                }
            }
        } else if runtime.keyMonitoringUnavailable {
            Section {
                NoticeRow(text: "暂时无法读取按键。可以在“辅助功能”里关掉再打开 MoliSwitch 试试。") {
                    Button("打开系统设置…") {
                        runtime.openAccessibilitySystemSettings()
                    }
                }
            }
        }

        if (runtime.shiftEnglishEnabled || runtime.slashCommandSwitchingEnabled)
            && runtime.inputSourceIndicatorEnabled
        {
            Section {
                NoticeRow(text: "系统会在切换输入法后在光标旁提示，这会让按 Shift 或 / 时卡一下。") {
                    Button("关闭提示") {
                        runtime.setInputSourceIndicatorEnabled(false)
                    }
                }
            } footer: {
                SectionFooter("可以在“通用”里重新打开。如果某个 App 里还没变化，重新打开这个 App 就行。")
            }
        }
    }

    // MARK: - Shift

    private var shiftSection: some View {
        Section {
            Toggle("按住 Shift 时打英文", isOn: $runtime.shiftEnglishEnabled)
            LabeledContent("切英文的按键") {
                ShiftCategoryToggles(categories: $runtime.shiftEnglishCategories)
            }
            .disabled(!runtime.shiftEnglishEnabled)
            Toggle("松开 Shift 后切回原输入法", isOn: $runtime.shiftRestoresOnRelease)
                .disabled(!runtime.shiftEnglishEnabled)
            applicationCountRow(
                count: runtime.shiftAppRules.rules.isEmpty
                    ? "全部用上面的设置"
                    : "\(runtime.shiftAppRules.rules.count) 个单独设置",
                enabled: runtime.shiftEnglishEnabled
            )
        } header: {
            Text("按住 Shift")
        } footer: {
            SectionFooter(
                "用中文输入法时，按住 Shift 打勾选的这几类键，会先切到英文再打出来。"
                    + "比如只勾“字母”，Shift + A 打出 A，Shift + 1 仍是中文的“！”。"
                    + "按住 Shift 时第一个要切的键切到英文，之后到松开 Shift 打的都是英文。"
                    + "松开 Shift 后切回原来的输入法；关掉“松开 Shift 后切回原输入法”的话，就一直用英文，要自己切回。"
                    + "只按 Shift，或者 Shift 加回车、Tab、空格、方向键，不会切换。"
                    + "每个 App 可以在“应用”的“⇧ 英文”里单独设置或关闭。"
            )
        }
    }

    // MARK: - Slash commands

    private var slashCommandSection: some View {
        Section {
            Toggle("输入斜杠命令时切到英文", isOn: $runtime.slashCommandSwitchingEnabled)
            Toggle("按空格或 Tab 后切回原输入法", isOn: $runtime.slashCommandRestoresOnSpace)
                .disabled(!runtime.slashCommandSwitchingEnabled)
            applicationCountRow(
                count: runtime.slashCommandApps.apps.isEmpty
                    ? "还没有勾选"
                    : "\(runtime.slashCommandApps.apps.count) 个",
                enabled: runtime.slashCommandSwitchingEnabled
            )
        } header: {
            Text("斜杠命令")
        } footer: {
            SectionFooter(
                "在“应用”里勾选了“/ 命令”的 App 里，在输入框开头输入 / 时，会切到英文输入法并打出 /。"
                    + "终端里看不到光标位置，把输入删空后再按 / 也会切英文。"
                    + "按回车或 Esc、离开输入框，或者把 / 删掉后，切回原来的输入法。"
                    + "命令参数要打中文的，可以打开“按空格或 Tab 后切回原输入法”。"
            )
        }
    }

    /// How many applications use a feature, with a way to the table that sets it.
    private func applicationCountRow(count: String, enabled: Bool) -> some View {
        LabeledContent("App") {
            HStack(spacing: 8) {
                Text(count)
                    .foregroundStyle(.secondary)
                Button("在“应用”里设置") {
                    sidebarSelection = .applications
                }
                .buttonStyle(.link)
            }
        }
        .disabled(!enabled)
    }

    // MARK: - Terminal

    @ViewBuilder
    private var terminalSections: some View {
        Section {
            Toggle("在终端和 iTerm 中按前台程序切换", isOn: $runtime.terminalSwitchingEnabled)

            if runtime.terminalAccessDenied {
                NoticeRow(text: "没有权限读取终端的当前标签页。") {
                    Button("打开系统设置…") {
                        runtime.openAutomationSystemSettings()
                    }
                }
            }
        } header: {
            Text("终端程序")
        } footer: {
            SectionFooter(
                "运行下面的程序时切到对应输入法，退出后回到终端应用自己的设置。"
                    + "按程序名匹配（不区分大小写），tmux 里的程序也能识别；"
                    + "ssh 远程运行的程序无法识别，只能给 ssh 整体设置。"
                    + "第一次使用时系统会请求“自动化”权限。"
            )
        }

        Section {
            if runtime.commandRuleSet.rules.isEmpty {
                Text("还没有添加程序。")
                    .foregroundStyle(.secondary)
            }

            ForEach(runtime.commandRuleSet.rules) { rule in
                HStack(spacing: 8) {
                    Text(rule.command)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    InputSourcePicker(
                        title: rule.command + " 的输入法",
                        selection: Binding(
                            get: { runtime.selectedInputSourceID(for: rule) },
                            set: { runtime.setInputSourceID($0, forCommand: rule.command) }
                        ),
                        roleChoices: runtime.ruleRoleChoices,
                        otherChoices: runtime.inputSourceChoices(for: rule)
                    )
                    .labelsHidden()
                    .fixedSize()

                    Button {
                        runtime.removeCommandRule(rule.command)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除")
                    .accessibilityLabel("删除 " + rule.command)
                }
            }

            HStack(spacing: 8) {
                TextField("程序名", text: $newCommand, prompt: Text("程序名，如 claude、codex、vim"))
                    .labelsHidden()
                    .onSubmit(addNewCommand)

                Button("添加", action: addNewCommand)
                    .disabled(CommandRuleSet.normalizedCommand(newCommand).isEmpty)
            }

            if let context = runtime.lastTerminalContext,
               !context.displayName.isEmpty,
               runtime.commandRuleSet.rule(matchingAnyOf: context.candidates) == nil
            {
                Button("添加刚才在终端中运行的“" + context.displayName + "”") {
                    runtime.addCommandRule(context.displayName)
                }
                .buttonStyle(.link)
            }
        }
        .disabled(!runtime.commandRuleEditingEnabled)
    }

    private func addNewCommand() {
        if runtime.addCommandRule(newCommand) {
            newCommand = ""
        }
    }

    // MARK: - Text fields

    @ViewBuilder
    private var fieldSections: some View {
        Section {
            Toggle("在地址栏中切换输入法", isOn: $runtime.addressBarSwitchingEnabled)

            InputSourcePicker(
                title: "输入法",
                selection: $runtime.addressBarInputSourceSelection,
                roleChoices: runtime.ruleRoleChoices,
                otherChoices: runtime.addressBarInputSourceChoices
            )
            .disabled(!runtime.addressBarSwitchingEnabled)
        } header: {
            Text("浏览器地址栏")
        } footer: {
            SectionFooter("支持 Safari、Chrome、Edge、Brave、Vivaldi、Opera 和 Firefox。")
        }

        Section {
            if runtime.fieldRuleSet.rules.isEmpty {
                Text("还没有记住的输入框。")
                    .foregroundStyle(.secondary)
            }

            ForEach(runtime.fieldRuleGroups, id: \.bundleIdentifier) { group in
                ForEach(group.rules) { rule in
                    FieldRuleRow(runtime: runtime, rule: rule, applicationName: group.applicationName)
                }
            }
        } header: {
            Text("已记住的输入框")
        } footer: {
            SectionFooter(
                "在要记住的输入框里点一下，切到想用的输入法，然后点菜单栏图标，选择“记住当前输入框”。"
                    + "光标进入输入框时切到对应输入法，离开后回到应用自己的设置。"
                    + "网页改版后可能认不出原来的输入框，需要重新记住。"
            )
        }
        .disabled(!runtime.fieldRuleEditingEnabled)
    }
}

private struct FieldRuleRow: View {
    @ObservedObject var runtime: AppRuntime
    let rule: FieldRule
    let applicationName: String
    @State private var label = ""

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                TextField("名称", text: $label)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .onSubmit(commitLabel)
                    .accessibilityLabel("输入框名称")

                Text(applicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            InputSourcePicker(
                title: rule.label + " 的输入法",
                selection: Binding(
                    get: { runtime.selectedInputSourceID(for: rule) },
                    set: { runtime.setInputSourceID($0, forFieldRule: rule.id) }
                ),
                roleChoices: runtime.ruleRoleChoices,
                otherChoices: runtime.inputSourceChoices(for: rule)
            )
            .labelsHidden()
            .fixedSize()

            Button {
                runtime.removeFieldRule(rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
            .accessibilityLabel("删除 " + rule.label)
        }
        .onAppear {
            label = rule.label
        }
        .onChange(of: rule.label) { _, newValue in
            label = newValue
        }
        .onDisappear(perform: commitLabel)
    }

    private func commitLabel() {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label = rule.label
        } else if label != rule.label {
            runtime.renameFieldRule(rule.id, to: label)
        }
    }
}
