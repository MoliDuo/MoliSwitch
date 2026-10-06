import MoliSwitchCore
import SwiftUI

/// Switching while typing: English while Shift is held, and for slash
/// commands. Which applications use them is set with each application.
struct TypingPage: View {
    @ObservedObject var runtime: AppRuntime
    @AppStorage("selectedSidebarItem") private var sidebarSelection: SidebarItem = .typing

    var body: some View {
        Form {
            shiftSection
            slashCommandSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Shift

    private var shiftSection: some View {
        Section {
            Toggle("按住 Shift 时打英文", isOn: $runtime.shiftEnglishEnabled)
            LabeledContent("切英文的按键") {
                ShiftKeyPicker(keyCodes: $runtime.shiftEnglishKeyCodes)
            }
            .disabled(!runtime.shiftEnglishEnabled)
            Toggle("松开 Shift 后切回原输入法", isOn: $runtime.shiftRestoresOnRelease)
                .disabled(!runtime.shiftEnglishEnabled)
            applicationCountRow(
                count: runtime.shiftAppRules.rules.isEmpty
                    ? "全部用上面的设置"
                    : "\(runtime.shiftAppRules.rules.count) 个单独设置",
                enabled: runtime.shiftEnglishEnabled
            )
        } header: {
            Text("按住 Shift")
        } footer: {
            SectionFooter(
                "用中文输入法时，按住 Shift 打选中的键（蓝色），会先切到英文再打出来。"
                    + "上面的勾选框一次选中或取消一类键，下面的键可以一个一个点。"
                    + "比如只选 ?，Shift + / 打出 ?，Shift + ; 仍是中文的“：”。"
                    + "按住 Shift 时第一个要切的键切到英文，之后到松开 Shift 打的都是英文。"
                    + "松开 Shift 后切回原来的输入法；关掉“松开 Shift 后切回原输入法”的话，就一直用英文，要自己切回。"
                    + "只按 Shift，或者 Shift 加回车、Tab、空格、方向键，不会切换。"
                    + "每个 App 可以在“应用”里选中后，在右边单独设置或关闭。"
            )
        }
    }

    // MARK: - Slash commands

    private var slashCommandSection: some View {
        Section {
            Toggle("输入斜杠命令时切到英文", isOn: $runtime.slashCommandSwitchingEnabled)
            Toggle("按空格或 Tab 后切回原输入法", isOn: $runtime.slashCommandRestoresOnSpace)
                .disabled(!runtime.slashCommandSwitchingEnabled)
            applicationCountRow(
                count: runtime.slashCommandApps.apps.isEmpty
                    ? "还没有勾选"
                    : "\(runtime.slashCommandApps.apps.count) 个",
                enabled: runtime.slashCommandSwitchingEnabled
            )
        } header: {
            Text("斜杠命令")
        } footer: {
            SectionFooter(
                "在“应用”里打开了“输入 / 命令时切到英文”的 App 里，在输入框开头输入 / 时，会切到英文输入法并打出 /。"
                    + "终端里看不到光标位置，把输入删空后再按 / 也会切英文。"
                    + "按回车或 Esc、离开输入框，或者把 / 删掉后，切回原来的输入法。"
                    + "命令参数要打中文的，可以打开“按空格或 Tab 后切回原输入法”。"
            )
        }
    }

    /// How many applications use a feature, with a way to the table that sets it.
    private func applicationCountRow(count: String, enabled: Bool) -> some View {
        LabeledContent("App") {
            HStack(spacing: 8) {
                Text(count)
                    .foregroundStyle(.secondary)
                Button("在“应用”里设置") {
                    sidebarSelection = .applications
                }
                .buttonStyle(.link)
            }
        }
        .disabled(!enabled)
    }
}
