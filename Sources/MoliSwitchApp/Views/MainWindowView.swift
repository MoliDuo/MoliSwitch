import AppKit
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case applications
    case typing
    case suggestions
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "应用"
        case .typing: "打字时切换"
        case .suggestions: "优化建议"
        case .general: "通用"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .typing: "keyboard"
        case .suggestions: "lightbulb"
        case .general: "gearshape"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var runtime: AppRuntime
    @AppStorage("selectedSidebarItem") private var selection: SidebarItem = .applications

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section {
                    sidebarRow(.applications)
                    sidebarRow(.typing)
                    sidebarRow(.suggestions, badge: runtime.suggestions.count)
                }
                Section {
                    sidebarRow(.general)
                }
            }
            // The sidebar toggle also keeps the toolbar on pages without
            // toolbar items, so the title stays in place when switching pages.
            .navigationSplitViewColumnWidth(200)
        } detail: {
            detail
                .navigationTitle(selection.title)
                .safeAreaInset(edge: .top, spacing: 0) {
                    notices
                }
        }
        .frame(minWidth: 960, minHeight: 520)
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

    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    /// The tag has to be the outermost modifier: a list row whose tag sits
    /// under another modifier, such as a badge, cannot be selected.
    private func sidebarRow(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .badge(badge)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .applications:
            ApplicationsPage(runtime: runtime)
        case .typing:
            TypingPage(runtime: runtime)
        case .suggestions:
            SuggestionsPage(runtime: runtime)
        case .general:
            GeneralPage(runtime: runtime)
        }
    }

    /// Problems that need the user, on every page: a rule file that could not
    /// be read, a missing permission, a system setting that gets in the way.
    /// Confirmations and counts are not shown here.
    @ViewBuilder
    private var notices: some View {
        let showsStatus = runtime.primaryStatus.map { $0.severity != .info } ?? false
        let needsAccessibility = !runtime.accessibilityTrusted && usesAccessibility
        let showsKeyMonitoring = runtime.accessibilityTrusted && runtime.keyMonitoringUnavailable
        let showsIndicator = (runtime.shiftEnglishEnabled || runtime.slashCommandSwitchingEnabled)
            && runtime.inputSourceIndicatorEnabled

        if showsStatus || needsAccessibility || showsKeyMonitoring || showsIndicator {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if showsStatus, let status = runtime.primaryStatus {
                        statusRow(status)
                    }

                    if needsAccessibility {
                        NoticeRow(text: "需要“辅助功能”权限才能读取按键、识别光标所在的输入框。") {
                            Button("打开系统设置…") {
                                runtime.requestAccessibilityTrust()
                                runtime.openAccessibilitySystemSettings()
                            }
                        }
                    } else if showsKeyMonitoring {
                        NoticeRow(text: "暂时无法读取按键。可以在“辅助功能”里关掉再打开 MoliSwitch 试试。") {
                            Button("打开系统设置…") {
                                runtime.openAccessibilitySystemSettings()
                            }
                        }
                    }

                    if showsIndicator {
                        NoticeRow(text: "系统会在切换输入法后在光标旁提示，这会让按 Shift 或 / 时卡一下。") {
                            Button("关闭提示") {
                                runtime.setInputSourceIndicatorEnabled(false)
                            }
                        }
                        .help("可以在“通用”里重新打开。如果某个 App 里还没变化，重新打开这个 App 就行。")
                    }
                }
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.bar)
        }
    }

    /// Whether anything that is turned on reads keys or text fields.
    private var usesAccessibility: Bool {
        runtime.shiftEnglishEnabled
            || runtime.slashCommandSwitchingEnabled
            || runtime.addressBarSwitchingEnabled
            || !runtime.fieldRuleSet.rules.isEmpty
    }

    private func statusRow(_ status: StatusMessage) -> some View {
        NoticeRow(text: status.text, severity: status.severity) {
            if runtime.hasStorageFailure {
                Button("重新读取") {
                    runtime.reloadRulesFromDisk()
                }
                Button("在 Finder 中显示") {
                    runtime.revealRulesFileInFinder()
                }
            } else if runtime.scanStatus != nil {
                Button("重试") {
                    runtime.refreshApplications()
                }
                .disabled(runtime.isScanning)
            }
        }
    }
}
