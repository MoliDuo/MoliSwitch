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
        if switchesNothing {
            return "关闭"
        }
        if categories.count == ShiftKeyCategory.allCases.count {
            return "全部"
        }
        return ShiftKeyCategory.allCases.compactMap { category -> String? in
            switch state(of: category) {
            case .all: category.shortTitle
            case .some: "\(category.shortTitle) \(ShiftKey.keyCodes(in: category).intersection(keyCodes).count) 个"
            case .none: nil
            }
        }
        .joined(separator: "、")
    }
}

/// The keys that may switch to English with Shift held: a checkbox for each
/// kind of key, which chooses or clears all of them, and the keys themselves,
/// laid out like the keyboard, to choose one by one.
struct ShiftKeyPicker: View {
    @Binding var keyCodes: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                ForEach(ShiftKeyCategory.allCases, id: \.self) { category in
                    Toggle(sources: keyBindings(in: category), isOn: \.self) {
                        Text(category.shortTitle)
                    }
                    .toggleStyle(.checkbox)
                    .help(category.title + "：" + category.examples)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(ShiftKey.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 3) {
                        ForEach(row) { key in
                            KeyCap(key: key, isOn: binding(for: key.keyCode))
                        }
                    }
                    // Like the keys of a keyboard, each row a little to the right.
                    .padding(.leading, CGFloat(index) * 6)
                }
            }
        }
    }

    private func binding(for keyCode: Int) -> Binding<Bool> {
        Binding(
            get: { keyCodes.contains(keyCode) },
            set: { isOn in
                if isOn {
                    keyCodes.insert(keyCode)
                } else {
                    keyCodes.remove(keyCode)
                }
            }
        )
    }

    private func keyBindings(in category: ShiftKeyCategory) -> [Binding<Bool>] {
        ShiftKey.all.filter { $0.category == category }.map { binding(for: $0.keyCode) }
    }

    private struct KeyCap: View {
        let key: ShiftKey
        @Binding var isOn: Bool

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                Text(key.shifted)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(ShiftKey.label(forKeyCode: key.keyCode) + (isOn ? "：切英文" : "：不切换"))
            .accessibilityLabel(ShiftKey.label(forKeyCode: key.keyCode))
            .accessibilityValue(isOn ? "切英文" : "不切换")
        }
    }
}
