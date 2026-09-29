import AppKit
import MoliSwitchCore
import SwiftUI

/// The input source of each installed application.
struct ApplicationsPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var icons = ApplicationIconCache()

    var body: some View {
        VStack(spacing: 0) {
            defaultInputSourceRow
            Divider()
            content
        }
        .searchable(text: $runtime.searchText, placement: .toolbar, prompt: "搜索应用")
        .toolbar {
            ToolbarItem {
                Picker("显示", selection: $runtime.applicationListScope) {
                    Text("全部").tag(ApplicationListScope.all)
                    Text("已设置").tag(ApplicationListScope.configured)
                    Text("未设置").tag(ApplicationListScope.unconfigured)
                }
                .pickerStyle(.segmented)
                .help("显示哪些应用")
            }

            ToolbarItem {
                Button {
                    runtime.reloadInputSources()
                    runtime.refreshApplications()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新扫描应用和输入法")
                .disabled(runtime.isScanning)
            }
        }
    }

    private var defaultInputSourceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("默认输入法")
                Text("没有单独设置的应用使用这个输入法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            InputSourcePicker(
                title: "默认输入法",
                selection: $runtime.defaultInputSourceSelection,
                fixedChoices: [InputSourceChoice(id: AppRuntime.noSwitchInputSourceID, name: "不切换")],
                roleChoices: runtime.ruleRoleChoices,
                otherChoices: runtime.defaultInputSourceChoices
            )
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if runtime.isScanning && runtime.installedApplications.isEmpty {
            ProgressView("正在查找已安装的应用…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if runtime.filteredInstalledApplications.isEmpty {
            ContentUnavailableView(
                "没有匹配的应用",
                systemImage: "magnifyingglass",
                description: Text("换个搜索词，或在工具栏中选择“全部”。")
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table
        }
    }

    private var table: some View {
        Table(runtime.filteredInstalledApplications) {
            TableColumn("应用") { application in
                HStack(spacing: 10) {
                    icon(for: application)

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
                InputSourcePicker(
                    title: application.name + " 的输入法",
                    selection: Binding(
                        get: { runtime.selectedInputSourceID(for: application) },
                        set: { runtime.setInputSourceID($0, for: application) }
                    ),
                    fixedChoices: [
                        InputSourceChoice(
                            id: AppRuntime.followDefaultInputSourceID,
                            name: runtime.followDefaultChoiceTitle
                        ),
                        InputSourceChoice(id: AppRuntime.noSwitchInputSourceID, name: "不切换"),
                    ],
                    roleChoices: runtime.ruleRoleChoices,
                    otherChoices: runtime.inputSourceChoices(for: application)
                )
                .labelsHidden()
                .disabled(!runtime.ruleEditingEnabled)
            }
            .width(min: 180, ideal: 220, max: 280)

            TableColumn("/ 命令") { application in
                featureCheckbox(
                    title: application.name + " 输入斜杠命令时切到英文",
                    isOn: Binding(
                        get: { runtime.usesSlashCommands(application) },
                        set: { runtime.setUsesSlashCommands($0, for: application) }
                    ),
                    featureEnabled: runtime.slashCommandSwitchingEnabled,
                    editingEnabled: runtime.slashCommandAppEditingEnabled,
                    help: "在输入框开头输入 / 时切到英文"
                )
            }
            .width(56)

            TableColumn("⇧ 英文") { application in
                featureCheckbox(
                    title: application.name + " 按住 Shift 时打英文",
                    isOn: Binding(
                        get: { runtime.usesShiftEnglish(application) },
                        set: { runtime.setUsesShiftEnglish($0, for: application) }
                    ),
                    featureEnabled: runtime.shiftEnglishEnabled,
                    editingEnabled: runtime.shiftExcludedAppEditingEnabled,
                    help: "按住 Shift 时打英文"
                )
            }
            .width(56)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    /// Whether an application uses a feature that is turned on in 自动切换.
    private func featureCheckbox(
        title: String,
        isOn: Binding<Bool>,
        featureEnabled: Bool,
        editingEnabled: Bool,
        help: String
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!featureEnabled || !editingEnabled)
            .frame(maxWidth: .infinity)
            .help(featureEnabled ? help : "在“自动切换”里打开后才能勾选")
    }

    @ViewBuilder
    private func icon(for application: InstalledApplication) -> some View {
        Group {
            if let url = application.url {
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
}

/// Application icons by path. A new scan generation drops them, since an
/// update can change an application's icon.
@MainActor
final class ApplicationIconCache {
    private var icons: [String: NSImage] = [:]
    private var generation = 0

    func icon(for url: URL, generation: Int) -> NSImage {
        if generation != self.generation {
            icons.removeAll()
            self.generation = generation
        }
        if let icon = icons[url.path] {
            return icon
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 24, height: 24)
        icons[url.path] = icon
        return icon
    }
}
