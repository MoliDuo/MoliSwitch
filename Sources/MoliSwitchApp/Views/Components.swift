import SwiftUI

/// Menu of input sources in groups separated by dividers: fixed choices such as
/// "不切换", then the 中文 and 英文 roles, then the remaining input sources.
struct InputSourcePicker: View {
    let title: String
    @Binding var selection: String
    var fixedChoices: [InputSourceChoice] = []
    var roleChoices: [InputSourceChoice] = []
    var otherChoices: [InputSourceChoice] = []

    var body: some View {
        let groups = [fixedChoices, roleChoices, otherChoices].filter { !$0.isEmpty }

        Picker(title, selection: $selection) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider()
                }
                ForEach(groups[index]) { choice in
                    Text(choice.name).tag(choice.id)
                }
            }
        }
    }
}

/// A warning or error with the actions that resolve it.
struct NoticeRow<Actions: View>: View {
    let text: String
    var severity: StatusSeverity = .warning
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(severity == .error ? .red : .orange)
                .accessibilityHidden(true)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            actions
        }
    }
}

extension NoticeRow where Actions == EmptyView {
    init(text: String, severity: StatusSeverity = .warning) {
        self.init(text: text, severity: severity) { EmptyView() }
    }
}

/// Separate view so the update button observes the updater state directly.
struct CheckForUpdatesButton: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        Button("检查更新…") {
            controller.checkForUpdates()
        }
        .disabled(!controller.canCheckForUpdates)
    }
}

/// Explanatory text under a form section. Leading-aligned like the rows above
/// it; grouped forms align footers to the trailing edge by default.
struct SectionFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
