import Foundation

/// A JSON value, for the fields of a usage event.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// A string, or null when there is none.
    public static func optional(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    public static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

/// One line of the usage log: when something happened and what.
///
/// Written as a single flat JSON object, `t` (local time with milliseconds),
/// `mono` (milliseconds of system uptime, for exact intervals), `e` (the name
/// of the event), then the fields of the event. Includes typed characters and field text, except in password fields.
public struct UsageEvent: Equatable, Sendable {
    public let time: Date
    /// Milliseconds since the system started, which does not jump with the clock.
    public let mono: Double
    public let name: String
    public var fields: [String: JSONValue]

    public init(
        _ name: String,
        _ fields: [String: JSONValue] = [:],
        time: Date = Date(),
        mono: Double = UsageEvent.currentMonotonicMilliseconds()
    ) {
        self.time = time
        self.mono = mono
        self.name = name
        self.fields = fields
    }

    public static func currentMonotonicMilliseconds() -> Double {
        (ProcessInfo.processInfo.systemUptime * 10_000).rounded() / 10
    }

    /// The event as one line of JSON, without a line break.
    public func jsonLine() -> String {
        var object = fields
        object["t"] = .string(Self.timestamp(time))
        object["mono"] = .double(mono)
        object["e"] = .string(name)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard
            let data = try? encoder.encode(JSONValue.object(object)),
            let line = String(data: data, encoding: .utf8)
        else {
            return "{\"e\":\"encodingFailed\",\"name\":\"\(name)\"}"
        }
        return line
    }

    /// For example 2026-10-02T14:03:21.482+08:00.
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(
                dateSeparator: .dash,
                dateTimeSeparator: .standard,
                timeSeparator: .colon,
                timeZoneSeparator: .colon,
                includingFractionalSeconds: true,
                timeZone: timeZone
            )
        )
    }
}
