import MoliSwitchCore
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

extension ShiftKeyCategory {
    var title: String {
        switch self {
        case .letter: "字母"
        case .digit: "数字键上的符号"
        case .symbol: "其他符号"
        }
    }

    /// A few characters the keys type with Shift held.
    var examples: String {
        switch self {
        case .letter: "A B C"
        case .digit: "! @ # ( )"
        case .symbol: "? : \" _ { }"
        }
    }

    var shortTitle: String {
        switch self {
        case .letter: "字母"
        case .digit: "数字键"
        case .symbol: "符号"
        }
    }
}

extension ShiftEnglishOptions {
    /// Which keys switch, in a few words.
    var summary: String {
        if categories.isEmpty {
            return "关闭"
        }
        if categories.count == ShiftKeyCategory.allCases.count {
            return "全部"
        }
        return ShiftKeyCategory.allCases.filter(categories.contains).map(\.shortTitle).joined(separator: "、")
    }
}

/// A checkbox for each kind of key that may switch to English with Shift held.
struct ShiftCategoryToggles: View {
    @Binding var categories: Set<ShiftKeyCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ShiftKeyCategory.allCases, id: \.self) { category in
                Toggle(isOn: binding(for: category)) {
                    HStack(spacing: 6) {
                        Text(category.title)
                        Text(category.examples)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func binding(for category: ShiftKeyCategory) -> Binding<Bool> {
        Binding(
            get: { categories.contains(category) },
            set: { isOn in
                if isOn {
                    categories.insert(category)
                } else {
                    categories.remove(category)
                }
            }
        )
    }
}
