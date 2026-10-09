import Foundation

/// Times shown to people use Singapore time, whatever zone the Mac is in (MoliSpec 013).
public enum MoliTime {
    public static let zone = TimeZone(identifier: "Asia/Singapore") ?? TimeZone(secondsFromGMT: 8 * 3600)!

    /// Gregorian calendar in Singapore time; "a day" starts at Singapore midnight.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }()

    /// For example 2026年10月9日 21:03, for labels in the UI.
    public static func display(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = zone
        return date.formatted(style)
    }
}
