import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case applications
    case automation
    case suggestions
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "应用"
        case .automation: "自动切换"
        case .suggestions: "优化建议"
        case .general: "通用"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .automation: "wand.and.stars"
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
                    sidebarRow(.automation)
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
                    statusNotice
                }
        }
        .frame(minWidth: 720, minHeight: 480)
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
        case .automation:
            AutomationPage(runtime: runtime)
        case .suggestions:
            SuggestionsPage(runtime: runtime)
        case .general:
            GeneralPage(runtime: runtime)
        }
    }

    /// Problems that need the user, such as a rule file that could not be read.
    /// Confirmations and counts are not shown here.
    @ViewBuilder
    private var statusNotice: some View {
        if let status = runtime.primaryStatus, status.severity != .info {
            VStack(spacing: 0) {
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
                .font(.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                Divider()
            }
            .background(.bar)
        }
    }
}
