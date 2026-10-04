import MoliSwitchCore
import SwiftUI

/// Rule changes the usage log suggests. Nothing changes until one is applied,
/// and an applied one can be undone.
struct SuggestionsPage: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Form {
            Section {
                if runtime.suggestions.isEmpty {
                    Text(runtime.isAnalyzing ? "正在分析使用记录…" : "暂时没有建议。")
                        .foregroundStyle(.secondary)
                }
                ForEach(runtime.suggestions) { suggestion in
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
            } header: {
                HStack {
                    Text("建议")
                    Spacer()
                    Button("重新分析") { runtime.requestSuggestionRefresh() }
                        .disabled(runtime.isAnalyzing)
                }
            } footer: {
                Text("只读取本机的使用记录，不会联网。应用前不会改动任何规则。")
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
        }
        .formStyle(.grouped)
        .onAppear { runtime.requestSuggestionRefresh() }
    }
}
