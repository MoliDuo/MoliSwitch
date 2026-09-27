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
                    Text("图标隐藏后，再次打开 " + AppInfo.name + " 即可回到这个窗口。")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                InputSourcePicker(
                    title: "中文",
                    selection: $runtime.chineseInputSourceSelection,
                    fixedChoices: [automaticChoice(detected: runtime.detectedChineseInputSource)],
                    otherChoices: runtime.chineseInputSourceChoices
                )
                InputSourcePicker(
                    title: "英文",
                    selection: $runtime.englishInputSourceSelection,
                    fixedChoices: [automaticChoice(detected: runtime.detectedEnglishInputSource)],
                    otherChoices: runtime.englishInputSourceChoices
                )
            } header: {
                Text("输入法")
            } footer: {
                Text(
                    "设置里选“中文”或“英文”时，切到这里的输入法。"
                        + "列表里没有你的输入法？先在 系统设置 › 键盘 › 输入法 中添加。"
                )
                .foregroundStyle(.secondary)
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

    private func automaticChoice(detected: InputSource?) -> InputSourceChoice {
        InputSourceChoice(
            id: AppRuntime.automaticInputSourceID,
            name: "自动识别（" + (detected?.name ?? "未找到") + "）"
        )
    }
}

enum AppInfo {
    static let name = "MoliSwitch"

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
