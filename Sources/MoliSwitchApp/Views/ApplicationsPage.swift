import AppKit
import MoliSwitchCore
import SwiftUI

/// Every installed application with its input source, and beside the table
/// everything else the selected application has.
struct ApplicationsPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var icons = ApplicationIconCache()
    @AppStorage("showsApplicationInspector") private var showsInspector = true

    var body: some View {
        VStack(spacing: 0) {
            inputSourceHeader
            Divider()
            content
        }
        .searchable(text: $runtime.searchText, placement: .toolbar, prompt: "搜索应用")
        .inspector(isPresented: $showsInspector) {
            ApplicationInspector(runtime: runtime, application: selectedApplication, icons: icons)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
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

            ToolbarItem {
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("应用设置", systemImage: "sidebar.trailing")
                }
                .help(showsInspector ? "隐藏应用设置" : "显示应用设置")
            }
        }
    }

    private var selectedApplication: InstalledApplication? {
        guard let id = runtime.selectedApplicationID else { return nil }
        return runtime.displayApplications.first { $0.bundleIdentifier == id }
    }

    // MARK: - Input sources

    /// The default input source and the input sources the 中文 and 英文 rules
    /// switch to, side by side when there is room.
    private var inputSourceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    defaultPicker
                    rolePickers
                }
                VStack(alignment: .leading, spacing: 8) {
                    defaultPicker
                    rolePickers
                }
            }
            Text("没有单独设置的应用使用默认输入法；规则选“中文”“英文”时，切到这里选的输入法。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var defaultPicker: some View {
        InputSourcePicker(
            title: "默认",
            selection: $runtime.defaultInputSourceSelection,
            fixedChoices: [InputSourceChoice(id: AppRuntime.noSwitchInputSourceID, name: "不切换")],
            roleChoices: runtime.ruleRoleChoices,
            otherChoices: runtime.defaultInputSourceChoices
        )
        .fixedSize()
    }

    private var rolePickers: some View {
        HStack(spacing: 20) {
            InputSourcePicker(
                title: "中文",
                selection: $runtime.chineseInputSourceSelection,
                fixedChoices: [automaticChoice(detected: runtime.detectedChineseInputSource)],
                otherChoices: runtime.chineseInputSourceChoices
            )
            .fixedSize()
            .help("列表里没有你的输入法？先在 系统设置 › 键盘 › 输入法 中添加。")

            InputSourcePicker(
                title: "英文",
                selection: $runtime.englishInputSourceSelection,
                fixedChoices: [automaticChoice(detected: runtime.detectedEnglishInputSource)],
                otherChoices: runtime.englishInputSourceChoices
            )
            .fixedSize()
            .help("列表里没有你的输入法？先在 系统设置 › 键盘 › 输入法 中添加。")
        }
    }

    private func automaticChoice(detected: InputSource?) -> InputSourceChoice {
        InputSourceChoice(
            id: AppRuntime.automaticInputSourceID,
            name: "自动识别（" + (detected?.name ?? "未找到") + "）"
        )
    }

    // MARK: - Table

    @ViewBuilder
    private var content: some View {
        if runtime.isScanning, runtime.installedApplications.isEmpty {
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
        Table(runtime.filteredInstalledApplications, selection: $runtime.selectedApplicationID) {
            TableColumn("应用") { application in
                HStack(spacing: 10) {
                    ApplicationIcon(application: application, icons: icons, generation: runtime.iconCacheGeneration)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(application.name)
                            .lineLimit(1)

                        Text(subtitle(for: application))
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
                ApplicationInputSourcePicker(runtime: runtime, application: application)
                    .labelsHidden()
            }
            .width(min: 160, ideal: 200, max: 260)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func subtitle(for application: InstalledApplication) -> String {
        if application.url == nil {
            return "未找到应用"
        }
        return runtime.extrasSummary(for: application) ?? application.bundleIdentifier
    }
}

/// The input source rule of one application.
struct ApplicationInputSourcePicker: View {
    @ObservedObject var runtime: AppRuntime
    let application: InstalledApplication

    var body: some View {
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
        .disabled(!runtime.ruleEditingEnabled)
    }
}

/// An application's icon, or a placeholder when the application is gone.
struct ApplicationIcon: View {
    let application: InstalledApplication
    let icons: ApplicationIconCache
    let generation: Int
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = application.url {
                Image(nsImage: icons.icon(for: url, generation: generation))
                    .resizable()
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
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
