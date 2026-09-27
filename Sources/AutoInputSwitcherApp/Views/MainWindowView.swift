import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case applications
    case terminal
    case fields
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "应用"
        case .terminal: "终端程序"
        case .fields: "输入框"
        case .general: "通用"
        }
    }

    var systemImage: String {
        switch self {
        case .applications: "square.grid.2x2"
        case .terminal: "terminal"
        case .fields: "character.cursor.ibeam"
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
                    sidebarRow(.terminal)
                    sidebarRow(.fields)
                }
                Section {
                    sidebarRow(.general)
                }
            }
            .navigationSplitViewColumnWidth(200)
            .toolbar(removing: .sidebarToggle)
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

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .tag(item)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .applications:
            ApplicationsPage(runtime: runtime)
        case .terminal:
            TerminalPage(runtime: runtime)
        case .fields:
            FieldsPage(runtime: runtime)
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
