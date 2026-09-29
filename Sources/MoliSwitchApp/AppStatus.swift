import Foundation

enum StatusSeverity: Int, Comparable, Sendable {
    case info = 0
    case warning = 1
    case error = 2

    static func < (lhs: StatusSeverity, rhs: StatusSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A user facing status line. Severity is carried as data instead of being
/// inferred from the message text, so unrelated messages can never change the
/// colour of an error that is still outstanding.
struct StatusMessage: Equatable, Sendable {
    let text: String
    let severity: StatusSeverity

    init(text: String, severity: StatusSeverity = .info) {
        self.text = text
        self.severity = severity
    }

    static let rulesReadFailure = StatusMessage(
        text: "规则读取失败，已暂停规则编辑；原文件未修改。",
        severity: .error
    )

    static let commandRulesReadFailure = StatusMessage(
        text: "终端程序规则读取失败，已暂停编辑；原文件未修改。",
        severity: .error
    )

    static let fieldRulesReadFailure = StatusMessage(
        text: "输入框规则读取失败，已暂停编辑；原文件未修改。",
        severity: .error
    )

    static let slashCommandAppsReadFailure = StatusMessage(
        text: "斜杠命令的 App 名单读取失败，已暂停编辑；原文件未修改。",
        severity: .error
    )

    static let rulesSaveFailure = StatusMessage(
        text: "规则保存失败，修改未生效。",
        severity: .error
    )

    static let rulesReloaded = StatusMessage(text: "规则已重新读取")

    static let rulesSaved = StatusMessage(text: "已保存")
}
