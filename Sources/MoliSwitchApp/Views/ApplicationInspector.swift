import MoliSwitchCore
import SwiftUI

/// Everything one application has: its input source, slash commands and Shift,
/// and depending on the application, programs in the terminal, the address bar
/// and remembered text fields.
struct ApplicationInspector: View {
    @ObservedObject var runtime: AppRuntime
    let application: InstalledApplication?
    let icons: ApplicationIconCache

    var body: some View {
        if let application {
            ApplicationSettingsForm(runtime: runtime, application: application, icons: icons)
                // Fresh state, such as the Shift mode, for each application.
                .id(application.bundleIdentifier)
        } else {
            ContentUnavailableView(
                "没有选中应用",
                systemImage: "sidebar.trailing",
                description: Text("在左边选一个应用，查看并修改它的全部设置。")
            )
        }
    }
}

private struct ApplicationSettingsForm: View {
    @ObservedObject var runtime: AppRuntime
    let application: InstalledApplication
    let icons: ApplicationIconCache
    @AppStorage("selectedSidebarItem") private var sidebarSelection: SidebarItem = .applications
    @State private var newCommand = ""

    var body: some View {
        Form {
            Section {
                header
                LabeledContent("输入法") {
                    ApplicationInputSourcePicker(runtime: runtime, application: application)
                        .labelsHidden()
                }
            }

            typingSection

            if runtime.supportsTerminal(bundleIdentifier: application.bundleIdentifier) {
                terminalSections
            }

            if AddressBarDetector.isBrowser(bundleIdentifier: application.bundleIdentifier) {
                addressBarSection
            }

            fieldSection
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ApplicationIcon(
                application: application,
                icons: icons,
                generation: runtime.iconCacheGeneration,
                size: 32
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(application.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(application.url == nil ? "未找到应用" : application.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .help(application.url?.path ?? application.bundleIdentifier)
    }

    // MARK: - Typing

    private var typingSection: some View {
        Section {
            Toggle(
                "输入 / 命令时切到英文",
                isOn: Binding(
                    get: { runtime.usesSlashCommands(application) },
                    set: { runtime.setUsesSlashCommands($0, for: application) }
                )
            )
            .disabled(!runtime.slashCommandSwitchingEnabled || !runtime.slashCommandAppEditingEnabled)

            if !runtime.slashCommandSwitchingEnabled {
                turnOnRow("斜杠命令没有打开。")
            }

            ShiftOptionsEditor(runtime: runtime, application: application)
                .disabled(!runtime.shiftEnglishEnabled || !runtime.shiftAppRuleEditingEnabled)

            if !runtime.shiftEnglishEnabled {
                turnOnRow("按住 Shift 打英文没有打开。")
            }
        } header: {
            Text("打字时")
        }
    }

    private func turnOnRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .foregroundStyle(.secondary)
            Button("在“打字时切换”里打开") {
                sidebarSelection = .typing
            }
            .buttonStyle(.link)
        }
        .font(.callout)
    }

    // MARK: - Terminal

    private var terminalSections: some View {
        Section {
            Toggle("按前台程序切换", isOn: $runtime.terminalSwitchingEnabled)

            if runtime.terminalAccessDenied {
                NoticeRow(text: "没有权限读取终端的当前标签页。") {
                    Button("打开系统设置…") {
                        runtime.openAutomationSystemSettings()
                    }
                }
            }

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
                .disabled(!runtime.commandRuleEditingEnabled)
            }

            HStack(spacing: 8) {
                TextField("程序名", text: $newCommand, prompt: Text("程序名，如 claude、vim"))
                    .labelsHidden()
                    .onSubmit(addNewCommand)

                Button("添加", action: addNewCommand)
                    .disabled(CommandRuleSet.normalizedCommand(newCommand).isEmpty)
            }
            .disabled(!runtime.commandRuleEditingEnabled)

            if let context = runtime.lastTerminalContext,
               let command = context.candidates.first,
               runtime.commandRuleSet.rule(matchingAnyOf: context.candidates) == nil
            {
                Button("添加刚才在终端中运行的“" + context.displayName + "”") {
                    runtime.addCommandRule(command)
                }
                .buttonStyle(.link)
                .disabled(!runtime.commandRuleEditingEnabled)
            }
        } header: {
            Text("终端程序")
        } footer: {
            SectionFooter(
                "终端和 iTerm2 共用这些程序。运行它们时切到对应输入法，退出后回到上面的输入法。"
                    + "按程序名匹配（不区分大小写），tmux 里的程序也能识别；"
                    + "ssh 到远程机器时，按标签页标题认出远端的程序（Claude Code、vim，以及会把命令写进标题的 shell 都会设置标题），"
                    + "认不出来时按 ssh 的设置。"
                    + "第一次使用时系统会请求“自动化”权限。"
            )
        }
    }

    private func addNewCommand() {
        if runtime.addCommandRule(newCommand) {
            newCommand = ""
        }
    }

    // MARK: - Address bar

    private var addressBarSection: some View {
        Section {
            Toggle("在地址栏中切换输入法", isOn: $runtime.addressBarSwitchingEnabled)

            InputSourcePicker(
                title: "地址栏",
                selection: $runtime.addressBarInputSourceSelection,
                roleChoices: runtime.ruleRoleChoices,
                otherChoices: runtime.addressBarInputSourceChoices
            )
            .disabled(!runtime.addressBarSwitchingEnabled)
        } header: {
            Text("浏览器地址栏")
        } footer: {
            SectionFooter("所有浏览器共用这个设置：Safari、Chrome、Edge、Brave、Vivaldi、Opera 和 Firefox。")
        }
    }

    // MARK: - Text fields

    private var fieldSection: some View {
        Section {
            let rules = runtime.fieldRules(for: application.bundleIdentifier)
            if rules.isEmpty {
                Text("还没有记住的输入框。")
                    .foregroundStyle(.secondary)
            }

            ForEach(rules) { rule in
                FieldRuleRow(runtime: runtime, rule: rule)
            }
        } header: {
            Text("记住的输入框")
        } footer: {
            SectionFooter(
                "在要记住的输入框里点一下，切到想用的输入法，然后点菜单栏图标，选择“记住当前输入框”。"
                    + "光标进入输入框时切到对应输入法，离开后回到上面的输入法。"
                    + "网页改版后可能认不出原来的输入框，需要重新记住。"
            )
        }
        .disabled(!runtime.fieldRuleEditingEnabled)
    }
}

/// Chooses whether an application follows the Shift settings in 打字时切换,
/// turns Shift off, or has keys of its own.
private struct ShiftOptionsEditor: View {
    private enum Mode: Hashable {
        case followDefault
        case off
        case custom
    }

    @ObservedObject var runtime: AppRuntime
    let application: InstalledApplication
    /// Kept apart from the saved options, so unticking every key in 自定义
    /// keeps the checkboxes on screen.
    @State private var mode: Mode = .followDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("按住 Shift 打英文") {
                Picker("方式", selection: modeBinding) {
                    Text("默认").tag(Mode.followDefault)
                    Text("关闭").tag(Mode.off)
                    Text("自定义").tag(Mode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            switch mode {
            case .followDefault:
                Text("用“打字时切换”里的设置：" + runtime.globalShiftOptions.summary + "。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .off:
                Text("在这个 App 里按住 Shift 不切换输入法。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .custom:
                ShiftKeyPicker(keyCodes: optionBinding(\.keyCodes))
                Toggle("松开 Shift 后切回原输入法", isOn: optionBinding(\.restoresOnRelease))
            }
        }
        .onAppear {
            switch runtime.shiftOptions(for: application) {
            case nil: mode = .followDefault
            case let options? where options.switchesNothing: mode = .off
            case _?: mode = .custom
            }
        }
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                mode = newMode
                switch newMode {
                case .followDefault:
                    runtime.setShiftOptions(nil, for: application)
                case .off:
                    runtime.setShiftOptions(.off, for: application)
                case .custom:
                    let global = runtime.globalShiftOptions
                    runtime.setShiftOptions(global.switchesNothing ? .all : global, for: application)
                }
            }
        )
    }

    private func optionBinding<Value>(_ keyPath: WritableKeyPath<ShiftEnglishOptions, Value>) -> Binding<Value> {
        Binding(
            get: { (runtime.shiftOptions(for: application) ?? runtime.globalShiftOptions)[keyPath: keyPath] },
            set: { newValue in
                var options = runtime.shiftOptions(for: application) ?? runtime.globalShiftOptions
                options[keyPath: keyPath] = newValue
                runtime.setShiftOptions(options, for: application)
            }
        )
    }
}

private struct FieldRuleRow: View {
    @ObservedObject var runtime: AppRuntime
    let rule: FieldRule
    @State private var label = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("名称", text: $label)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .onSubmit(commitLabel)
                .accessibilityLabel("输入框名称")

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
