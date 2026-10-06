import MoliSwitchCore
import SwiftUI

/// Rule changes the usage log suggests, in groups by what they change.
/// Nothing changes until one is applied, and an applied one can be undone.
struct SuggestionsPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var confirmsClearingUsageLog = false

    var body: some View {
        Form {
            Section {
                if !runtime.usageLoggingEnabled {
                    NoticeRow(text: "打开下面的“记录使用日志”后，才能根据使用情况给出建议。")
                } else if runtime.suggestions.isEmpty {
                    Text(runtime.isAnalyzing ? "正在分析使用记录…" : "暂时没有建议。")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("建议")
                    Spacer()
                    Button("重新分析") { runtime.requestSuggestionRefresh() }
                        .disabled(runtime.isAnalyzing)
                }
            } footer: {
                Text(
                    "只读取本机最近 \(UsageAnalyzer.analyzedDays) 天的使用记录，不会联网。"
                        + "看的是每次进入 App 或终端程序时规则选得对不对，偶尔手动切换不会改规则。应用前不会改动任何规则。"
                )
            }

            ForEach(RuleSuggestion.Kind.allCases, id: \.self) { kind in
                let group = runtime.suggestions.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(kind.title) {
                        ForEach(group) { suggestion in
                            SuggestionRow(runtime: runtime, suggestion: suggestion)
                        }
                    }
                }
            }

            if !runtime.appliedSuggestions.isEmpty {
                Section("已应用") {
                    ForEach(runtime.appliedSuggestions) { applied in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(applied.title)
                                Text(applied.appliedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("撤销") { runtime.undoSuggestion(applied) }
                        }
                    }
                }
            }

            Section {
                Toggle("记录使用日志", isOn: $runtime.usageLoggingEnabled)
                HStack {
                    Button("打开日志文件夹") { runtime.revealUsageLogFolder() }
                    Button("清除日志…") { confirmsClearingUsageLog = true }
                }
            } header: {
                Text("使用日志")
            } footer: {
                SectionFooter(
                    "记下前台 App、输入法切换、按键的种类和时间，用来分析并优化配置。"
                        + "只保存在这台 Mac 上，保留 30 天。会记录按键、输入框信息和输入框里的文字（密码框和密码管理器除外）。"
                )
            }
            .confirmationDialog("清除全部使用日志？", isPresented: $confirmsClearingUsageLog) {
                Button("清除", role: .destructive) { runtime.clearUsageLog() }
            }
        }
        .formStyle(.grouped)
        .onAppear { runtime.requestSuggestionRefresh() }
    }
}

private struct SuggestionRow: View {
    @ObservedObject var runtime: AppRuntime
    let suggestion: RuleSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.title).font(.headline)
            Text(suggestion.evidence)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("应用") { runtime.applySuggestion(suggestion) }
                    .buttonStyle(.borderedProminent)
                Button("忽略") { runtime.dismissSuggestion(suggestion) }
            }
        }
        .padding(.vertical, 4)
    }
}

private extension RuleSuggestion.Kind {
    var title: String {
        switch self {
        case .application: "应用"
        case .command: "终端程序"
        case .field: "输入框"
        case .shift: "Shift 按键"
        }
    }
}
