import AppKit
import MoliSwitchCore
import SwiftUI
import UniformTypeIdentifiers

/// Applications in which a slash at the start of the input starts a command,
/// which is typed with the English input source.
struct SlashCommandsPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var icons = ApplicationIconCache()
    @State private var runningApplications: [InstalledApplication] = []

    var body: some View {
        Form {
            if !runtime.accessibilityTrusted {
                Section {
                    NoticeRow(text: "需要“辅助功能”权限才能看到输入的斜杠。") {
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

            Section {
                Toggle("输入斜杠命令时切到英文", isOn: $runtime.slashCommandSwitchingEnabled)
                Toggle("按空格后切回原输入法", isOn: $runtime.slashCommandRestoresOnSpace)
                    .disabled(!runtime.slashCommandSwitchingEnabled)
            } footer: {
                SectionFooter(
                    "在下面的 App 里，在输入框开头输入 / 时，会切到英文输入法并打出 /。"
                        + "按回车或 Esc、离开输入框，或者把 / 删掉后，切回原来的输入法；按 Tab 补全不会切回。"
                        + "命令参数要打中文的，可以打开“按空格后切回原输入法”。"
                )
            }

            Section("App") {
                if runtime.slashCommandApps.apps.isEmpty {
                    Text("还没有添加 App。")
                        .foregroundStyle(.secondary)
                }

                ForEach(runtime.slashCommandApps.apps) { app in
                    HStack(spacing: 8) {
                        icon(forBundleIdentifier: app.bundleIdentifier)

                        Text(app.applicationName)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Button {
                            runtime.removeSlashCommandApp(bundleIdentifier: app.bundleIdentifier)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                        .accessibilityLabel("删除 " + app.applicationName)
                    }
                }

                Menu("添加 App") {
                    let candidates = runningApplications.filter {
                        !runtime.slashCommandApps.contains(bundleIdentifier: $0.bundleIdentifier)
                    }
                    if !candidates.isEmpty {
                        Section("正在运行") {
                            ForEach(candidates) { application in
                                Button(application.name) {
                                    runtime.addSlashCommandApp(application)
                                }
                            }
                        }
                        Divider()
                    }
                    Button("选择其他 App…", action: chooseApplication)
                }
                .fixedSize()
            }
            .disabled(!runtime.slashCommandAppEditingEnabled)
        }
        .formStyle(.grouped)
        .onAppear {
            runtime.refreshAccessibilityTrust()
            refreshRunningApplications()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may come back from System Settings having allowed it.
            runtime.refreshAccessibilityTrust()
            refreshRunningApplications()
        }
    }

    private func icon(forBundleIdentifier bundleIdentifier: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                Image(nsImage: icons.icon(for: url, generation: runtime.iconCacheGeneration))
                    .resizable()
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    private func refreshRunningApplications() {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var seen: Set<String> = []
        runningApplications = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application -> InstalledApplication? in
                guard
                    let bundleIdentifier = application.bundleIdentifier,
                    bundleIdentifier != ownBundleIdentifier,
                    seen.insert(bundleIdentifier).inserted
                else {
                    return nil
                }
                return InstalledApplication(
                    name: application.localizedName ?? bundleIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    url: application.bundleURL
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "添加"

        guard
            panel.runModal() == .OK,
            let url = panel.url,
            let bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        else {
            return
        }

        let name = FileManager.default.displayName(atPath: url.path)
        runtime.addSlashCommandApp(
            InstalledApplication(
                name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                bundleIdentifier: bundleIdentifier,
                url: url
            )
        )
    }
}
