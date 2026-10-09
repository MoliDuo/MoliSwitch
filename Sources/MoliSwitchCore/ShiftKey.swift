import Foundation

/// A key that types a character, by its place on the keyboard, so it is the
/// same key whatever the input source. Characters are those of the US layout.
public struct ShiftKey: Equatable, Hashable, Identifiable, Sendable {
    public var id: Int {
        keyCode
    }

    public let keyCode: Int
    /// Typed without Shift.
    public let base: String
    /// Typed with Shift.
    public let shifted: String
    public let category: ShiftKeyCategory

    public init(keyCode: Int, base: String, shifted: String, category: ShiftKeyCategory) {
        self.keyCode = keyCode
        self.base = base
        self.shifted = shifted
        self.category = category
    }

    /// The keys in the rows of the keyboard, top to bottom, left to right.
    public static let rows: [[ShiftKey]] = [
        [
            .init(keyCode: 50, base: "`", shifted: "~", category: .symbol),
            .init(keyCode: 18, base: "1", shifted: "!", category: .digit),
            .init(keyCode: 19, base: "2", shifted: "@", category: .digit),
            .init(keyCode: 20, base: "3", shifted: "#", category: .digit),
            .init(keyCode: 21, base: "4", shifted: "$", category: .digit),
            .init(keyCode: 23, base: "5", shifted: "%", category: .digit),
            .init(keyCode: 22, base: "6", shifted: "^", category: .digit),
            .init(keyCode: 26, base: "7", shifted: "&", category: .digit),
            .init(keyCode: 28, base: "8", shifted: "*", category: .digit),
            .init(keyCode: 25, base: "9", shifted: "(", category: .digit),
            .init(keyCode: 29, base: "0", shifted: ")", category: .digit),
            .init(keyCode: 27, base: "-", shifted: "_", category: .symbol),
            .init(keyCode: 24, base: "=", shifted: "+", category: .symbol),
        ],
        [
            .init(keyCode: 12, base: "q", shifted: "Q", category: .letter),
            .init(keyCode: 13, base: "w", shifted: "W", category: .letter),
            .init(keyCode: 14, base: "e", shifted: "E", category: .letter),
            .init(keyCode: 15, base: "r", shifted: "R", category: .letter),
            .init(keyCode: 17, base: "t", shifted: "T", category: .letter),
            .init(keyCode: 16, base: "y", shifted: "Y", category: .letter),
            .init(keyCode: 32, base: "u", shifted: "U", category: .letter),
            .init(keyCode: 34, base: "i", shifted: "I", category: .letter),
            .init(keyCode: 31, base: "o", shifted: "O", category: .letter),
            .init(keyCode: 35, base: "p", shifted: "P", category: .letter),
            .init(keyCode: 33, base: "[", shifted: "{", category: .symbol),
            .init(keyCode: 30, base: "]", shifted: "}", category: .symbol),
            .init(keyCode: 42, base: "\\", shifted: "|", category: .symbol),
        ],
        [
            .init(keyCode: 0, base: "a", shifted: "A", category: .letter),
            .init(keyCode: 1, base: "s", shifted: "S", category: .letter),
            .init(keyCode: 2, base: "d", shifted: "D", category: .letter),
            .init(keyCode: 3, base: "f", shifted: "F", category: .letter),
            .init(keyCode: 5, base: "g", shifted: "G", category: .letter),
            .init(keyCode: 4, base: "h", shifted: "H", category: .letter),
            .init(keyCode: 38, base: "j", shifted: "J", category: .letter),
            .init(keyCode: 40, base: "k", shifted: "K", category: .letter),
            .init(keyCode: 37, base: "l", shifted: "L", category: .letter),
            .init(keyCode: 41, base: ";", shifted: ":", category: .symbol),
            .init(keyCode: 39, base: "'", shifted: "\"", category: .symbol),
        ],
        [
            .init(keyCode: 6, base: "z", shifted: "Z", category: .letter),
            .init(keyCode: 7, base: "x", shifted: "X", category: .letter),
            .init(keyCode: 8, base: "c", shifted: "C", category: .letter),
            .init(keyCode: 9, base: "v", shifted: "V", category: .letter),
            .init(keyCode: 11, base: "b", shifted: "B", category: .letter),
            .init(keyCode: 45, base: "n", shifted: "N", category: .letter),
            .init(keyCode: 46, base: "m", shifted: "M", category: .letter),
            .init(keyCode: 43, base: ",", shifted: "<", category: .symbol),
            .init(keyCode: 47, base: ".", shifted: ">", category: .symbol),
            .init(keyCode: 44, base: "/", shifted: "?", category: .symbol),
        ],
    ]

    public static let all: [ShiftKey] = rows.flatMap(\.self)

    private static let byKeyCode: [Int: ShiftKey] = Dictionary(uniqueKeysWithValues: all.map { ($0.keyCode, $0) })

    /// The keypad digits count as the digits of the number row.
    private static let keypadDigits: [Int: Int] = [
        82: 29, 83: 18, 84: 19, 85: 20, 86: 21, 87: 23, 88: 22, 89: 26, 91: 28, 92: 25,
    ]

    public static func key(forKeyCode keyCode: Int) -> ShiftKey? {
        byKeyCode[keypadDigits[keyCode] ?? keyCode]
    }

    public static func keyCodes(in category: ShiftKeyCategory) -> Set<Int> {
        Set(all.filter { $0.category == category }.map(\.keyCode))
    }

    /// How a key is shown, for example "Shift + /（?）".
    public static func label(forKeyCode keyCode: Int) -> String {
        guard let key = key(forKeyCode: keyCode) else { return "Shift + 键 \(keyCode)" }
        return key.category == .letter ? "Shift + \(key.base.uppercased())" : "Shift + \(key.base)（\(key.shifted)）"
    }
}
