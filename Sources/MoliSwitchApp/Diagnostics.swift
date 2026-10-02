import Foundation
import os
import MoliSwitchCore

/// Diagnostics for slash commands, Shift and terminals. Every line goes to the
/// system log, read with
/// `log stream --predicate 'subsystem == "com.moli.MoliSwitch"' --level debug`,
/// and to the usage log as a `diag` event, so one file tells the whole story.
/// Only kinds of keys, decisions, input source identifiers and timings are
/// logged, never what was typed.
enum Diagnostics {
    enum Category: String {
        case slash
        case shift
        case terminal
    }

    enum Level: String {
        case debug
        case info
        case error
    }

    private static let loggers: [Category: Logger] = [
        .slash: Logger(subsystem: "com.moli.MoliSwitch", category: "slash"),
        .shift: Logger(subsystem: "com.moli.MoliSwitch", category: "shift"),
        .terminal: Logger(subsystem: "com.moli.MoliSwitch", category: "terminal"),
    ]

    /// Where the lines go besides the system log. Set by the runtime, and
    /// called from any thread.
    nonisolated(unsafe) static var sink: (@Sendable (Category, Level, String) -> Void)?

    static func record(_ category: Category, _ level: Level, _ message: String) {
        let logger = loggers[category] ?? Logger(subsystem: "com.moli.MoliSwitch", category: category.rawValue)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        sink?(category, level, message)
    }

    /// Milliseconds since a moment taken with ContinuousClock.now.
    static func milliseconds(since start: ContinuousClock.Instant) -> String {
        let elapsed = ContinuousClock.now - start
        let (seconds, attoseconds) = elapsed.components
        return String(format: "%.1f", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
