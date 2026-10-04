import Foundation

/// Reads the usage log and suggests rules that match how the user really
/// switches. Nothing is changed here; the suggestions are only shown.
public struct UsageAnalyzer: Sendable {
    public struct Thresholds: Sendable {
        /// Manual switches in an application before one target is suggested.
        public var minimumManualSwitches = 8
        /// Share of those switches that went to the same input source.
        public var manualSwitchShare = 0.7
        /// Letter keys typed in a field before a rule for it is suggested.
        public var minimumFieldLetters = 100
        /// Share of those keys typed with the same input source.
        public var fieldShare = 0.9
        /// A switch undone this quickly is a flicker, not a choice.
        public var flickerMilliseconds = 150.0

        public init() {}
    }

    /// What the rules do now, so a suggestion is never made for what is
    /// already set up.
    public struct CurrentRules: Sendable {
        /// The input source each application ends up with, by bundle
        /// identifier, with roles already turned into real input sources.
        public var appTargets: [String: String]
        /// What applications without a rule end up with, if anything.
        public var defaultTarget: String?
        public var fieldRules: [FieldRule]
        /// Real input source identifiers, with their names, for the text.
        public var inputSourceNames: [String: String]

        public init(
            appTargets: [String: String],
            defaultTarget: String? = nil,
            fieldRules: [FieldRule],
            inputSourceNames: [String: String]
        ) {
            self.appTargets = appTargets
            self.defaultTarget = defaultTarget
            self.fieldRules = fieldRules
            self.inputSourceNames = inputSourceNames
        }

        func target(for bundleIdentifier: String) -> String? {
            appTargets[bundleIdentifier] ?? defaultTarget
        }
    }

    public var thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    private struct FieldKey: Hashable {
        var bundleIdentifier: String
        var signature: FieldSignature
    }

    /// Suggestions from log lines in time order.
    public func suggestions(fromLines lines: [String], current: CurrentRules) -> [RuleSuggestion] {
        var applicationNames: [String: String] = [:]
        var manualSwitches: [String: [String: Int]] = [:]
        var lastManual: [String: (from: String?, to: String?, mono: Double)] = [:]
        var fieldSignatures: [String: FieldSignature?] = [:]
        var fieldLetters: [FieldKey: [String: Int]] = [:]

        let decoder = JSONDecoder()
        for line in lines {
            guard
                let data = line.data(using: .utf8),
                case .object(let event)? = try? decoder.decode(JSONValue.self, from: data),
                case .string(let kind)? = event["e"],
                case .string(let app)? = event["app"]
            else { continue }

            switch kind {
            case "appFocus":
                if case .string(let name)? = event["appName"] { applicationNames[app] = name }
            case "fieldFocus":
                fieldSignatures[app] = Self.signature(from: event["field"])
            case "manualSwitch":
                guard case .string(let to)? = event["to"] else { continue }
                let from = event["from"].flatMap(Self.string)
                if case .bool(true)? = event["ownSwitch"] { continue }
                if case .bool(true)? = event["undoesPrevious"] { continue }
                let mono = event["mono"].flatMap(Self.number) ?? 0
                if let last = lastManual[app], mono - last.mono < thresholds.flickerMilliseconds,
                   last.from == to, let lastTo = last.to {
                    // A flicker: take the first half back.
                    manualSwitches[app]?[lastTo, default: 1] -= 1
                    lastManual[app] = nil
                    continue
                }
                manualSwitches[app, default: [:]][to, default: 0] += 1
                lastManual[app] = (from, to, mono)
            case "key":
                guard
                    case .string(let category)? = event["category"], category == "letter",
                    case .string(let source)? = event["current"],
                    let signature = fieldSignatures[app] ?? nil
                else { continue }
                fieldLetters[FieldKey(bundleIdentifier: app, signature: signature), default: [:]][source, default: 0] += 1
            default:
                break
            }
        }

        func name(_ id: String) -> String { current.inputSourceNames[id] ?? id }
        func appName(_ bundle: String) -> String { applicationNames[bundle] ?? bundle }

        var result: [RuleSuggestion] = []

        for (app, counts) in manualSwitches.sorted(by: { $0.key < $1.key }) {
            let total = counts.values.filter { $0 > 0 }.reduce(0, +)
            guard total >= thresholds.minimumManualSwitches,
                  let top = counts.max(by: { $0.value < $1.value }),
                  Double(top.value) / Double(total) >= thresholds.manualSwitchShare,
                  current.target(for: app) != top.key
            else { continue }
            result.append(
                RuleSuggestion(
                    id: "app:\(app)=\(top.key)",
                    title: "\(appName(app)) 默认用 \(name(top.key))",
                    evidence: "在 \(appName(app)) 里手动切换了 \(total) 次，其中 \(top.value) 次切到 \(name(top.key))；现在的规则是 \(current.target(for: app).map(name) ?? "未设置")。",
                    action: .setAppRule(bundleIdentifier: app, applicationName: appName(app), inputSourceID: top.key)
                )
            )
        }

        for (key, counts) in fieldLetters.sorted(by: { "\($0.key.bundleIdentifier)\($0.key.signature.descriptor ?? "")" < "\($1.key.bundleIdentifier)\($1.key.signature.descriptor ?? "")" }) {
            let total = counts.values.reduce(0, +)
            guard total >= thresholds.minimumFieldLetters,
                  let top = counts.max(by: { $0.value < $1.value }),
                  Double(top.value) / Double(total) >= thresholds.fieldShare,
                  current.target(for: key.bundleIdentifier) != top.key,
                  // The address bar has a setting of its own.
                  !AddressBarDetector.isAddressBar(bundleIdentifier: key.bundleIdentifier, field: key.signature),
                  !current.fieldRules.contains(where: {
                      $0.bundleIdentifier == key.bundleIdentifier && $0.signature.matches(key.signature)
                  })
            else { continue }
            let label = key.signature.suggestedLabel
            result.append(
                RuleSuggestion(
                    id: "field:\(key.bundleIdentifier):\(key.signature.role):\(key.signature.identifier ?? key.signature.descriptor ?? "")=\(top.key)",
                    title: "\(appName(key.bundleIdentifier)) 的“\(label)”用 \(name(top.key))",
                    evidence: "在这个输入框里敲了 \(total) 个字母键，\(top.value) 个是在 \(name(top.key)) 下敲的；App 默认是 \(current.target(for: key.bundleIdentifier).map(name) ?? "未设置")。",
                    action: .addFieldRule(
                        bundleIdentifier: key.bundleIdentifier,
                        applicationName: appName(key.bundleIdentifier),
                        signature: key.signature,
                        inputSourceID: top.key
                    )
                )
            )
        }

        return result
    }

    private static func string(_ value: JSONValue) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }

    private static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .double(let number): return number
        case .int(let number): return Double(number)
        default: return nil
        }
    }

    private static func signature(from value: JSONValue?) -> FieldSignature? {
        guard case .object(let field)? = value, case .string(let role)? = field["role"] else { return nil }
        var ancestors: [String] = []
        if case .array(let items)? = field["ancestors"] {
            ancestors = items.compactMap(string)
        }
        var isWeb = false
        if case .bool(let web)? = field["web"] { isWeb = web }
        return FieldSignature(
            role: role,
            subrole: field["subrole"].flatMap(string),
            identifier: field["identifier"].flatMap(string),
            descriptor: field["descriptor"].flatMap(string),
            ancestorRoles: ancestors,
            isInWebArea: isWeb
        )
    }
}

extension UsageAnalyzer {
    /// Reads the lines of the given log files, oldest first.
    public static func lines(inLogFiles files: [URL]) -> [String] {
        files.flatMap { url -> [String] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").map(String.init)
        }
    }
}
