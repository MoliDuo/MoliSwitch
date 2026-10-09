import SwiftUI

struct GeneralPage: View {
    @ObservedObject var runtime: AppRuntime

    var body: some View {
        Form {
            Section {
                Toggle(
                    "登录时打开",
                    isOn: Binding(
                        get: { runtime.isLaunchAtLoginEnabled },
                        set: { runtime.setLaunchAtLoginEnabled($0) }
                    )
                )

                if runtime.launchAtLoginStatus == .requiresApproval {
                    NoticeRow(text: "需要在系统设置中允许。") {
                        Button("打开系统设置…") {
                            runtime.openLoginItemsSystemSettings()
                        }
                    }
                }

                Toggle("在菜单栏中显示图标", isOn: $runtime.showMenuBarIcon)
            } header: {
                Text("启动")
            } footer: {
                if !runtime.showMenuBarIcon {
                    SectionFooter("图标隐藏后，再次打开 " + AppInfo.name + " 即可回到这个窗口。")
                }
            }

            Section {
                Toggle(
                    "切换后在光标旁显示输入法",
                    isOn: Binding(
                        get: { runtime.inputSourceIndicatorEnabled },
                        set: { runtime.setInputSourceIndicatorEnabled($0) }
                    )
                )
            } footer: {
                SectionFooter(
                    "这是系统设置，对所有 App 生效。打开时，每次切换输入法，系统都会在光标旁提示一下，"
                        + "切换时会卡一下，按 Shift 或 / 切英文时最明显。建议关闭，菜单栏仍会显示当前输入法。"
                        + "改完后，如果某个 App 里还没变化，重新打开这个 App 就行。"
                )
            }

            Section("关于") {
                LabeledContent("版本", value: AppInfo.version)
                LabeledContent("已自动切换", value: "\(runtime.switchCount) 次")
                    .monospacedDigit()

                if let updateController = runtime.updateController {
                    HStack {
                        Spacer()
                        CheckForUpdatesButton(controller: updateController)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

enum AppInfo {
    static let name = "Moli Switch"

    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "开发版本"
        }
        if let build = info?["CFBundleVersion"] as? String, build != version {
            return version + "（" + build + "）"
        }
        return version
    }
}
