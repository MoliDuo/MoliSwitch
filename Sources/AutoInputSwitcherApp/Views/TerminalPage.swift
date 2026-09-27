import AutoInputSwitcherCore
import SwiftUI

/// Rules for programs running in Terminal and iTerm2, such as claude or vim.
struct TerminalPage: View {
    @ObservedObject var runtime: AppRuntime
    @State private var newCommand = ""

    var body: some View {
        Form {
            Section {
                Toggle("在终端和 iTerm 中按前台程序切换", isOn: $runtime.terminalSwitchingEnabled)

                if runtime.terminalAccessDenied {
                    NoticeRow(text: "没有权限读取终端的当前标签页。") {
                        Button("打开系统设置…") {
                            runtime.openAutomationSystemSettings()
                        }
                    }
                }
            } footer: {
                Text(
                    "运行下面的程序时切到对应输入法，退出后回到终端应用自己的设置。"
                        + "按程序名匹配（不区分大小写），tmux 里的程序也能识别；"
                        + "ssh 远程运行的程序无法识别，只能给 ssh 整体设置。"
                        + "第一次使用时系统会请求“自动化”权限。"
                )
                .foregroundStyle(.secondary)
            }

            Section("程序") {
                if runtime.commandRuleSet.rules.isEmpty {
                    Text("还没有添加程序。")
                        .foregroundStyle(.secondary)
                }

                ForEach(runtime.commandRuleSet.rules) { rule in
                    HStack(spacing: 8) {
                        Text(rule.command)
                            .font(.body.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        InputSourcePicker(
                            title: rule.command + " 的输入法",
                            selection: Binding(
                                get: { runtime.selectedInputSourceID(for: rule) },
                                set: { runtime.setInputSourceID($0, forCommand: rule.command) }
                            ),
                            roleChoices: runtime.ruleRoleChoices,
                            otherChoices: runtime.inputSourceChoices(for: rule)
                        )
                        .labelsHidden()
                        .fixedSize()

                        Button {
                            runtime.removeCommandRule(rule.command)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                        .accessibilityLabel("删除 " + rule.command)
                    }
                }

                HStack(spacing: 8) {
                    TextField("程序名", text: $newCommand, prompt: Text("程序名，如 claude、codex、vim"))
                        .labelsHidden()
                        .onSubmit(addNewCommand)

                    Button("添加", action: addNewCommand)
                        .disabled(CommandRuleSet.normalizedCommand(newCommand).isEmpty)
                }

                if let context = runtime.lastTerminalContext,
                   !context.displayName.isEmpty,
                   runtime.commandRuleSet.rule(matchingAnyOf: context.candidates) == nil
                {
                    Button("添加刚才在终端中运行的“" + context.displayName + "”") {
                        runtime.addCommandRule(context.displayName)
                    }
                    .buttonStyle(.link)
                }
            }
            .disabled(!runtime.commandRuleEditingEnabled)
        }
        .formStyle(.grouped)
    }

    private func addNewCommand() {
        if runtime.addCommandRule(newCommand) {
            newCommand = ""
        }
    }
}
