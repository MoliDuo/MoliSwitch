import AppKit
import MoliSwitchCore
import SwiftUI

/// The built-in rule for browser address bars, and remembered text fields.
struct FieldsPage: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Form {
            if !runtime.accessibilityTrusted {
                Section {
                    NoticeRow(text: "需要“辅助功能”权限才能识别光标所在的输入框。") {
                        Button("打开系统设置…") {
                            runtime.requestAccessibilityTrust()
                            runtime.openAccessibilitySystemSettings()
                        }
                    }
                }
            }

            Section {
                Toggle("在地址栏中切换输入法", isOn: $runtime.addressBarSwitchingEnabled)

                InputSourcePicker(
                    title: "输入法",
                    selection: $runtime.addressBarInputSourceSelection,
                    roleChoices: runtime.ruleRoleChoices,
                    otherChoices: runtime.addressBarInputSourceChoices
                )
                .disabled(!runtime.addressBarSwitchingEnabled)
            } header: {
                Text("浏览器地址栏")
            } footer: {
                SectionFooter("支持 Safari、Chrome、Edge、Brave、Vivaldi、Opera 和 Firefox。")
            }

            Section {
                if runtime.fieldRuleSet.rules.isEmpty {
                    Text("还没有记住的输入框。")
                        .foregroundStyle(.secondary)
                }

                ForEach(runtime.fieldRuleGroups, id: \.bundleIdentifier) { group in
                    ForEach(group.rules) { rule in
                        FieldRuleRow(runtime: runtime, rule: rule, applicationName: group.applicationName)
                    }
                }
            } header: {
                Text("已记住的输入框")
            } footer: {
                SectionFooter(
                    "在要记住的输入框里点一下，切到想用的输入法，然后点菜单栏图标，选择“记住当前输入框”。"
                        + "光标进入输入框时切到对应输入法，离开后回到应用自己的设置。"
                        + "网页改版后可能认不出原来的输入框，需要重新记住。"
                )
            }
            .disabled(!runtime.fieldRuleEditingEnabled)
        }
        .formStyle(.grouped)
        .onAppear {
            runtime.refreshAccessibilityTrust()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The user may come back from System Settings having allowed it.
            runtime.refreshAccessibilityTrust()
        }
    }
}

private struct FieldRuleRow: View {
    @ObservedObject var runtime: AppRuntime
    let rule: FieldRule
    let applicationName: String
    @State private var label = ""

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                TextField("名称", text: $label)
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .onSubmit(commitLabel)
                    .accessibilityLabel("输入框名称")

                Text(applicationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            InputSourcePicker(
                title: rule.label + " 的输入法",
                selection: Binding(
                    get: { runtime.selectedInputSourceID(for: rule) },
                    set: { runtime.setInputSourceID($0, forFieldRule: rule.id) }
                ),
                roleChoices: runtime.ruleRoleChoices,
                otherChoices: runtime.inputSourceChoices(for: rule)
            )
            .labelsHidden()
            .fixedSize()

            Button {
                runtime.removeFieldRule(rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除")
            .accessibilityLabel("删除 " + rule.label)
        }
        .onAppear {
            label = rule.label
        }
        .onChange(of: rule.label) { _, newValue in
            label = newValue
        }
        .onDisappear(perform: commitLabel)
    }

    private func commitLabel() {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label = rule.label
        } else if label != rule.label {
            runtime.renameFieldRule(rule.id, to: label)
        }
    }
}
