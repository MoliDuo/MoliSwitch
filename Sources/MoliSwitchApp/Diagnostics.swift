import Foundation
import os

/// Diagnostics for slash commands, read with
/// `log stream --predicate 'subsystem == "com.moli.MoliSwitch"' --level debug`.
/// Only kinds of keys, decisions, input source identifiers and timings are
/// logged, never what was typed.
enum Diagnostics {
    static let slash = Logger(subsystem: "com.moli.MoliSwitch", category: "slash")
    static let terminal = Logger(subsystem: "com.moli.MoliSwitch", category: "terminal")

    /// Milliseconds since a moment taken with ContinuousClock.now.
    static func milliseconds(since start: ContinuousClock.Instant) -> String {
        let elapsed = ContinuousClock.now - start
        let (seconds, attoseconds) = elapsed.components
        return String(format: "%.1f", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
