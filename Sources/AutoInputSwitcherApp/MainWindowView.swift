import AppKit
import AutoInputSwitcherCore
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var runtime: AppRuntime
    @State private var loadedIcons: [String: NSImage] = [:]
    @State private var showsSettings = false
    @State private var showsTerminalRules = false
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            applicationsContent
            Divider()
            footer
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: runtime.iconCacheGeneration) { _, _ in
            // Icons are cached by path and the scan invalidates them in one step.
            loadedIcons.removeAll()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("搜索应用或 Bundle ID", text: $runtime.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .accessibilityLabel("搜索应用或 Bundle ID")

            Picker("显示范围", selection: $runtime.applicationListScope) {
                Text("全部").tag(ApplicationListScope.all)
                Text("已配置").tag(ApplicationListScope.configured)
                Text("未配置").tag(ApplicationListScope.unconfigured)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("应用显示范围")

            Spacer(minLength: 0)

            Button {
                runtime.reloadInputSources()
                runtime.refreshApplications()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新扫描应用和输入法")
            .disabled(runtime.isScanning)
            .accessibilityLabel("刷新应用和输入法")

            Button {
                showsTerminalRules = true
            } label: {
                Image(systemName: "terminal")
            }
            .help("终端里按程序切换")
            .accessibilityLabel("终端里按程序切换")
            .sheet(isPresented: $showsTerminalRules) {
                TerminalRulesSheet(runtime: runtime)
            }

            Button {
                showsSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
            .accessibilityLabel("设置")
            .popover(isPresented: $showsSettings, arrowEdge: .bottom) {
                SettingsPanel(runtime: runtime, onQuit: onQuit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if runtime.isScanning && !runtime.installedApplications.isEmpty {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(runtime.statusText)
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(runtime.statusText)

            if runtime.hasStorageFailure {
                Button("重新读取") {
                    runtime.reloadRulesFromDisk()
                }

                Button("在 Finder 中显示规则文件") {
                    runtime.revealRulesFileInFinder()
                }
            } else if runtime.scanStatus != nil {
                Button("重试") {
                    runtime.refreshApplications()
                }
                .disabled(runtime.isScanning)
            }

            Spacer(minLength: 12)

            Text("已配置 \(runtime.configuredRuleCount) 个应用 · 已切换 \(runtime.switchCount) 次")
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "已配置 \(runtime.configuredRuleCount) 个应用，已切换 \(runtime.switchCount) 次"
                )
        }
        .font(.caption)
        .monospacedDigit()
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    // MARK: - Applications

    private var applicationsContent: some View {
        Group {
            if runtime.isScanning && runtime.installedApplications.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("正在扫描已安装应用...")
                    Text("首次加载可能需要几秒钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runtime.filteredInstalledApplications.isEmpty {
                ContentUnavailableView(
                    "没有匹配的应用",
                    systemImage: "magnifyingglass",
                    description: Text("调整搜索内容或切换到“全部”。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                applicationsList
            }
        }
    }

    private var applicationsList: some View {
        Table(runtime.filteredInstalledApplications) {
            TableColumn("应用") { application in
                HStack(spacing: 10) {
                    applicationIcon(for: application)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(application.name)
                            .lineLimit(1)

                        Text(application.url == nil ? "未找到应用" : application.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 3)
                .help(application.url?.path ?? application.bundleIdentifier)
            }

            TableColumn("输入法") { application in
                Picker(
                    "",
                    selection: Binding(
                        get: { runtime.selectedInputSourceID(for: application) },
                        set: { runtime.setInputSourceID($0, for: application) }
                    )
                ) {
                    Text(runtime.followDefaultChoiceTitle).tag(AppRuntime.followDefaultInputSourceID)
                    Text("不切换").tag(AppRuntime.noSwitchInputSourceID)
                    Divider()
                    ForEach(runtime.ruleRoleChoices) { choice in
                        Text(choice.name).tag(choice.id)
                    }

                    let otherChoices = runtime.inputSourceChoices(for: application)
                    if !otherChoices.isEmpty {
                        Divider()
                        ForEach(otherChoices) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                }
                .labelsHidden()
                .disabled(!runtime.ruleEditingEnabled)
                .accessibilityLabel("\(application.name) 的输入法")
            }
            .width(min: 180, ideal: 220, max: 280)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    @ViewBuilder
    private func applicationIcon(for application: InstalledApplication) -> some View {
        if let url = application.url {
            if let icon = loadedIcons[url.path] {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .onAppear { loadIcon(for: url) }
            }
        } else {
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var statusColor: Color {
        switch runtime.primaryStatus?.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info, .none:
            return .secondary
        }
    }

    private func loadIcon(for url: URL) {
        guard loadedIcons[url.path] == nil else {
            return
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        loadedIcons[url.path] = icon
    }
}

/// Rules for programs running in Terminal and iTerm2, such as claude or vim.
private struct TerminalRulesSheet: View {
    @ObservedObject var runtime: AppRuntime
    @Environment(\.dismiss) private var dismiss
    @State private var newCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("终端里按程序切换")
                .font(.headline)

            Toggle("在终端和 iTerm 里按前台程序切换", isOn: $runtime.terminalSwitchingEnabled)

            if runtime.terminalAccessDenied {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("没有权限读取终端的当前标签页。")
                    Spacer(minLength: 0)
                    Button("打开系统设置") {
                        runtime.openAutomationSystemSettings()
                    }
                }
                .font(.callout)
            }

            rulesList

            HStack(spacing: 8) {
                TextField("程序名，比如 claude、codex、vim", text: $newCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNewCommand)
                    .accessibilityLabel("要添加的程序名")

                Button("添加", action: addNewCommand)
                    .disabled(CommandRuleSet.normalizedCommand(newCommand).isEmpty)
            }
            .disabled(!runtime.commandRuleEditingEnabled)

            if let context = runtime.lastTerminalContext,
               !context.displayName.isEmpty,
               runtime.commandRuleSet.rule(matchingAnyOf: context.candidates) == nil
            {
                Button("添加刚才在终端里运行的“" + context.displayName + "”") {
                    runtime.addCommandRule(context.displayName)
                }
                .buttonStyle(.link)
                .disabled(!runtime.commandRuleEditingEnabled)
            }

            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder
    private var rulesList: some View {
        if runtime.commandRuleSet.rules.isEmpty {
            Text("还没有规则。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            List {
                ForEach(runtime.commandRuleSet.rules) { rule in
                    HStack(spacing: 8) {
                        Text(rule.command)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Picker(
                            "",
                            selection: Binding(
                                get: { runtime.selectedInputSourceID(for: rule) },
                                set: { runtime.setInputSourceID($0, forCommand: rule.command) }
                            )
                        ) {
                            ForEach(runtime.ruleRoleChoices) { choice in
                                Text(choice.name).tag(choice.id)
                            }

                            let otherChoices = runtime.inputSourceChoices(for: rule)
                            if !otherChoices.isEmpty {
                                Divider()
                                ForEach(otherChoices) { choice in
                                    Text(choice.name).tag(choice.id)
                                }
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .accessibilityLabel(rule.command + " 的输入法")

                        Button {
                            runtime.removeCommandRule(rule.command)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除规则")
                        .accessibilityLabel("删除 " + rule.command + " 的规则")
                    }
                    .disabled(!runtime.commandRuleEditingEnabled)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 120, maxHeight: 240)
        }
    }

    private var footer: String {
        "运行这些程序时切到对应输入法，退出后回到终端 App 自己的规则。"
            + "按程序名匹配（不区分大小写），tmux 里的程序也能识别；ssh 远程运行的程序看不到，只能给 ssh 整体设一条规则。"
            + "第一次使用时系统会请求“自动化”权限。"
    }

    private func addNewCommand() {
        if runtime.addCommandRule(newCommand) {
            newCommand = ""
        }
    }
}

/// Settings that are changed rarely, kept out of the main window.
private struct SettingsPanel: View {
    @ObservedObject var runtime: AppRuntime
    let onQuit: () -> Void

    var body: some View {
        Form {
            Section("通用") {
                Toggle(
                    "开机自启",
                    isOn: Binding(
                        get: { runtime.isLaunchAtLoginEnabled },
                        set: { runtime.setLaunchAtLoginEnabled($0) }
                    )
                )

                if runtime.launchAtLoginStatus == .requiresApproval {
                    Button("在系统设置中批准开机自启") {
                        runtime.openLoginItemsSystemSettings()
                    }
                }

                Toggle("显示菜单栏图标", isOn: $runtime.showMenuBarIcon)
            }

            Section {
                inputSourcePicker(
                    "中文",
                    selection: $runtime.chineseInputSourceSelection,
                    detected: runtime.detectedChineseInputSource,
                    choices: runtime.chineseInputSourceChoices
                )
                inputSourcePicker(
                    "英文",
                    selection: $runtime.englishInputSourceSelection,
                    detected: runtime.detectedEnglishInputSource,
                    choices: runtime.englishInputSourceChoices
                )
                inputSourcePicker(
                    "语音",
                    selection: $runtime.voiceInputSourceSelection,
                    detected: runtime.detectedVoiceInputSource,
                    choices: runtime.voiceInputSourceChoices
                )
            } header: {
                Text("输入法")
            } footer: {
                Text("App 规则里选“中文”或“英文”时，切到这里设置的输入法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("默认输入法", selection: $runtime.defaultInputSourceSelection) {
                    Text("不切换").tag(AppRuntime.noSwitchInputSourceID)
                    Divider()
                    ForEach(runtime.ruleRoleChoices) { choice in
                        Text(choice.name).tag(choice.id)
                    }

                    let otherChoices = runtime.defaultInputSourceChoices
                    if !otherChoices.isEmpty {
                        Divider()
                        ForEach(otherChoices) { choice in
                            Text(choice.name).tag(choice.id)
                        }
                    }
                }
            } footer: {
                Text("列表里设为“默认”的 App 切到这个输入法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("语音输入后切回原输入法", isOn: $runtime.voiceRestoreEnabled)
            } footer: {
                Text(voiceFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                HStack {
                    if let updateController = runtime.updateController {
                        CheckForUpdatesButton(controller: updateController)
                    }

                    Spacer()

                    Button("退出 AutoInputSwitcher", role: .destructive) {
                        onQuit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inputSourcePicker(
        _ title: String,
        selection: Binding<String>,
        detected: InputSource?,
        choices: [InputSourceChoice]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("自动识别（" + (detected?.name ?? "未找到") + "）")
                .tag(AppRuntime.automaticInputSourceID)
            Divider()
            ForEach(choices) { choice in
                Text(choice.name).tag(choice.id)
            }
        }
    }

    private var voiceFooter: String {
        if runtime.voiceRestoreEnabled && runtime.effectiveVoiceInputSource == nil {
            return "未找到豆包输入法，请在系统设置中添加，或在上面手动选择语音输入法。"
        }
        return "用豆包等语音输入法说完一句话后，自动切回之前的输入法。"
    }
}

/// Separate view so the update button observes the updater state directly.
private struct CheckForUpdatesButton: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Button("检查更新…") {
            controller.checkForUpdates()
        }
        .disabled(!controller.canCheckForUpdates)
        .accessibilityLabel("检查更新")
    }
}
