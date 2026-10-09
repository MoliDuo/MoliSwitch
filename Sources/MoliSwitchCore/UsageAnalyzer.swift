import Foundation

/// Reads the usage log and suggests rules that match how the user really
/// switches. Nothing is changed here; the suggestions are only shown.
///
/// Rules are judged by the times they were used, not by how often the user
/// switched: each time an application becomes active, or a terminal tab runs
/// another program, its rule picks an input source, and that is one visit.
/// A visit where the user typed counts; it was corrected when the user picked
/// another input source before typing. A rule is suggested only when most
/// visits were corrected, so a few switches among many visits that needed
/// none suggest nothing. Switches while typing are writing in both languages,
/// not a correction.
///
/// Shift is judged key by key: a key typed in Chinese with Shift held that
/// was deleted and typed again, a key switched to English that was deleted at
/// once, and switching back to English just after letting go of Shift.
public struct UsageAnalyzer: Sendable {
    public struct Thresholds: Sendable {
        /// Visits corrected to the same input source before a rule is suggested.
        public var minimumCorrections = 8
        /// Share of the visits with typing that were corrected to it.
        public var correctionShare = 0.5
        /// Share of the letters typed in those visits that were typed with it.
        public var correctedLetterShare = 0.6
        /// Letters typed in a visit for it to count; only passing by does not.
        public var minimumVisitLetters = 3
        /// A switch later than this after the rule was applied is not a correction.
        public var correctionMilliseconds = 10000.0
        /// A switch this soon after one of the app's own is the system, not the user.
        public var reactionMilliseconds = 200.0
        /// A switch undone this quickly is a flicker, not a choice.
        public var flickerMilliseconds = 150.0
        /// Letter keys typed in a field before a rule for it is suggested.
        public var minimumFieldLetters = 100
        /// Share of those keys typed with the same input source.
        public var fieldShare = 0.9

        /// A key deleted this soon after it was typed was a mistake.
        public var shiftDeleteMilliseconds = 3000.0
        /// How soon a deleted key has to be typed again to count as a retry.
        public var shiftRetypeMilliseconds = 10000.0
        /// Times a Shift key went wrong before a change is suggested.
        public var minimumShiftMistakes = 3
        /// Share of the key's Chinese uses retyped before it should switch.
        public var shiftEnableShare = 0.2
        /// Share of the key's switches deleted before it should not.
        public var shiftDisableShare = 0.3
        /// How soon after Shift switched back a switch to English undoes it.
        public var restoreUndoMilliseconds = 2000.0
        public var minimumRestoreUndos = 5
        public var restoreUndoShare = 0.3
        /// Share of the mistakes in one application for a change only there.
        public var singleApplicationShare = 0.8

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
        /// The input source of each program in the terminal, by
        /// `CommandRuleSet.matchKey`, with roles turned into input sources.
        public var commandTargets: [String: String]
        /// Whether programs in the terminal have rules of their own.
        public var commandRulesEnabled: Bool
        /// Whether Shift switches at all; no Shift suggestion when not.
        public var shiftEnabled: Bool
        public var globalShift: ShiftEnglishOptions
        /// The applications' own Shift settings, by bundle identifier.
        public var shiftAppRules: [String: ShiftEnglishOptions]
        /// Real input source identifiers, with their names, for the text.
        public var inputSourceNames: [String: String]

        public init(
            appTargets: [String: String],
            defaultTarget: String? = nil,
            fieldRules: [FieldRule],
            commandTargets: [String: String] = [:],
            commandRulesEnabled: Bool = true,
            shiftEnabled: Bool = false,
            globalShift: ShiftEnglishOptions = .all,
            shiftAppRules: [String: ShiftEnglishOptions] = [:],
            inputSourceNames: [String: String]
        ) {
            self.appTargets = appTargets
            self.defaultTarget = defaultTarget
            self.fieldRules = fieldRules
            self.commandTargets = commandTargets
            self.commandRulesEnabled = commandRulesEnabled
            self.shiftEnabled = shiftEnabled
            self.globalShift = globalShift
            self.shiftAppRules = shiftAppRules
            self.inputSourceNames = inputSourceNames
        }

        func target(for bundleIdentifier: String) -> String? {
            appTargets[bundleIdentifier] ?? defaultTarget
        }

        /// What a program gets: the rule of the first of its names that has
        /// one, or else the rule of the terminal.
        func target(forCandidates candidates: [String], in bundleIdentifier: String?) -> String? {
            for candidate in candidates {
                if let target = commandTargets[CommandRuleSet.matchKey(candidate)] {
                    return target
                }
            }
            return bundleIdentifier.flatMap(target(for:))
        }

        func shiftOptions(for bundleIdentifier: String?) -> ShiftEnglishOptions {
            bundleIdentifier.flatMap { shiftAppRules[$0] } ?? globalShift
        }
    }

    public var thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// Suggestions from log lines in time order.
    public func suggestions(fromLines lines: [String], current: CurrentRules) -> [RuleSuggestion] {
        var reader = Reader(thresholds: thresholds, current: current)
        for line in lines {
            reader.read(line)
        }
        reader.endVisit()

        var result = ruleSuggestions(reader, current: current)
        result += fieldSuggestions(reader, current: current)
        if current.shiftEnabled {
            result += shiftSuggestions(reader, current: current)
        }
        return result
    }

    // MARK: - Reading

    /// What a rule applies to: an application, or a program in the terminal.
    fileprivate enum Scope: Hashable, Comparable {
        case app(String)
        /// By `CommandRuleSet.matchKey`.
        case command(String)
    }

    fileprivate struct Visit {
        var scope: Scope
        var bundleIdentifier: String
        var tty: String?
        var start: Double
        /// The input source before the first switch.
        var initial: String?
        /// The input source picked before typing, if another one.
        var correction: String?
        var lastSwitchMono: Double?
        var letters: [String: Int] = [:]

        var letterCount: Int {
            letters.values.reduce(0, +)
        }
    }

    fileprivate struct ScopeStats {
        var visits = 0
        var corrections: [String: Int] = [:]
        var letters: [String: Int] = [:]
        /// The program's names, as last seen, and where it ran.
        var candidates: [String] = []
        var bundleIdentifier: String?
    }

    fileprivate struct FieldKey: Hashable {
        var bundleIdentifier: String
        var signature: FieldSignature
    }

    fileprivate struct ShiftKeyID: Hashable {
        var bundleIdentifier: String
        var keyCode: Int
    }

    fileprivate struct ShiftKeyStats {
        /// Typed in Chinese, and how often deleted and typed again.
        var chineseUses = 0
        var retyped = 0
        /// Switched to English, and how often deleted at once.
        var switches = 0
        var deleted = 0
    }

    fileprivate struct PendingShiftKey {
        enum Kind { case passedInChinese, switched }
        var id: ShiftKeyID
        var kind: Kind
        var mono: Double
        var deleted = false
    }

    fileprivate struct Reader {
        let thresholds: Thresholds
        let current: CurrentRules

        var applicationNames: [String: String] = [:]
        var commandNames: [String: String] = [:]
        var scopes: [Scope: ScopeStats] = [:]
        /// Terminals, which get rules by program instead of a rule of their own.
        var terminals: Set<String> = []
        var visit: Visit?
        /// Whether the focused field has a rule of its own, which then decides.
        var fieldHasOwnRule = false
        var fieldSignatures: [String: FieldSignature?] = [:]
        var fieldLetters: [FieldKey: [String: Int]] = [:]
        var lastManual: (from: String?, to: String, mono: Double)?

        var shiftKeys: [ShiftKeyID: ShiftKeyStats] = [:]
        var pendingShiftKey: PendingShiftKey?
        var restores: [String: (count: Int, undone: Int)] = [:]
        var pendingRestore: (app: String, mono: Double)?

        init(thresholds: Thresholds, current: CurrentRules) {
            self.thresholds = thresholds
            self.current = current
        }

        mutating func read(_ line: String) {
            // Most lines are keys; read those without parsing, and parse only
            // the few other events that are used.
            var text = line
            let quick: QuickEvent? = text.withUTF8 { buffer in
                if UsageAnalyzer.contains(UsageAnalyzer.keyEvent, in: buffer) {
                    return .key(KeyFields(buffer))
                }
                if UsageAnalyzer.contains(UsageAnalyzer.switchEvent, in: buffer) {
                    guard UsageAnalyzer.contains(UsageAnalyzer.shiftRestoreReason, in: buffer),
                          let app = UsageAnalyzer.value(after: UsageAnalyzer.appKey, in: buffer)
                    else { return nil }
                    return .shiftRestore(
                        app: app,
                        mono: UsageAnalyzer.number(after: UsageAnalyzer.monoKey, in: buffer) ?? 0
                    )
                }
                for (marker, kind) in UsageAnalyzer.parsedEvents where UsageAnalyzer.contains(marker, in: buffer) {
                    return .parse(kind)
                }
                return nil
            }

            switch quick {
            case nil:
                return
            case let .key(key):
                readKey(key)
            case let .shiftRestore(app, mono):
                restores[app, default: (0, 0)].count += 1
                pendingRestore = (app, mono)
            case let .parse(kind):
                guard
                    let data = line.data(using: .utf8),
                    let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    let app = event["app"] as? String
                else { return }
                let mono = (event["mono"] as? NSNumber)?.doubleValue ?? 0
                switch kind {
                case .appFocus: readAppFocus(event, app: app, mono: mono)
                case .terminal: readTerminal(event, app: app, mono: mono)
                case .fieldFocus: readFieldFocus(event, app: app)
                case .manualSwitch: readManualSwitch(event, app: app, mono: mono)
                }
            }
        }

        // MARK: Visits

        mutating func endVisit() {
            guard let visit else { return }
            self.visit = nil
            guard visit.letterCount >= thresholds.minimumVisitLetters else { return }
            var stats = scopes[visit.scope, default: ScopeStats()]
            stats.visits += 1
            stats.letters.merge(visit.letters, uniquingKeysWith: +)
            if let correction = visit.correction {
                stats.corrections[correction, default: 0] += 1
            }
            if stats.bundleIdentifier == nil {
                stats.bundleIdentifier = visit.bundleIdentifier
            }
            scopes[visit.scope] = stats
        }

        private mutating func startVisit(_ scope: Scope, app: String, tty: String?, mono: Double) {
            endVisit()
            visit = Visit(scope: scope, bundleIdentifier: app, tty: tty, start: mono)
        }

        /// The program in a terminal tab, from a logged terminal context.
        private mutating func program(in context: Any?, app: String) -> (scope: Scope, tty: String?)? {
            guard current.commandRulesEnabled,
                  let context = context as? [String: Any],
                  let candidates = context["candidates"] as? [String],
                  let first = candidates.first
            else { return nil }
            let name = CommandRuleSet.normalizedCommand(first)
            guard !name.isEmpty else { return nil }
            let key = CommandRuleSet.matchKey(name)
            commandNames[key] = name
            scopes[.command(key), default: ScopeStats()].candidates = candidates
            scopes[.command(key), default: ScopeStats()].bundleIdentifier = app
            terminals.insert(app)
            return (.command(key), context["tty"] as? String)
        }

        private mutating func readAppFocus(_ event: [String: Any], app: String, mono: Double) {
            if let name = event["appName"] as? String {
                applicationNames[app] = name
            }
            fieldHasOwnRule = false
            pendingShiftKey = nil
            pendingRestore = nil
            if let program = program(in: event["terminal"], app: app) {
                startVisit(program.scope, app: app, tty: program.tty, mono: mono)
            } else {
                startVisit(.app(app), app: app, tty: nil, mono: mono)
            }
        }

        /// Another tab or another program in the terminal, which applies its rule.
        private mutating func readTerminal(_ event: [String: Any], app: String, mono: Double) {
            guard let program = program(in: event["context"], app: app) else { return }
            if var visit, visit.bundleIdentifier == app {
                if visit.scope == program.scope, visit.tty == program.tty {
                    return
                }
                // Found after the terminal became active, before typing: the
                // same visit, and a switch already made was for the program.
                if case .app = visit.scope, visit.letterCount == 0 {
                    visit.scope = program.scope
                    visit.tty = program.tty
                    self.visit = visit
                    return
                }
            }
            startVisit(program.scope, app: app, tty: program.tty, mono: mono)
        }

        private mutating func readFieldFocus(_ event: [String: Any], app: String) {
            let signature = UsageAnalyzer.signature(from: event["field"])
            fieldSignatures[app] = signature
            fieldHasOwnRule = signature.map { signature in
                AddressBarDetector.isAddressBar(bundleIdentifier: app, field: signature)
                    || current.fieldRules.contains {
                        $0.bundleIdentifier == app && $0.signature.matches(signature)
                    }
            } ?? false
        }

        private mutating func readManualSwitch(_ event: [String: Any], app: String, mono: Double) {
            guard let to = event["to"] as? String,
                  event["ownSwitch"] as? Bool != true
            else { return }
            if let since = (event["sinceOwnSwitchMs"] as? NSNumber)?.doubleValue,
               since < thresholds.reactionMilliseconds
            {
                return
            }
            let from = event["from"] as? String
            defer { lastManual = (from, to, mono) }

            // Switching to English just after Shift switched back.
            if let restore = pendingRestore, restore.app == app,
               mono - restore.mono <= thresholds.restoreUndoMilliseconds,
               SlashCommandTracker.isKeyboardLayout(to)
            {
                restores[app, default: (0, 0)].undone += 1
                pendingRestore = nil
            }

            guard !fieldHasOwnRule, var visit, visit.bundleIdentifier == app else { return }
            let undoes = event["undoesPrevious"] as? Bool == true
                || lastManual.map { mono - $0.mono < thresholds.flickerMilliseconds && $0.from == to } ?? false
            if visit.letterCount == 0 {
                if visit.initial == nil {
                    visit.initial = from
                }
                if undoes || mono - visit.start <= thresholds.correctionMilliseconds {
                    visit.correction = to == visit.initial ? nil : to
                }
            }
            visit.lastSwitchMono = mono
            self.visit = visit
        }

        // MARK: Keys

        private mutating func readKey(_ key: KeyFields) {
            guard let app = key.app else { return }

            if key.isBackspace {
                if var pending = pendingShiftKey, pending.id.bundleIdentifier == app,
                   key.mono - pending.mono <= thresholds.shiftDeleteMilliseconds
                {
                    switch pending.kind {
                    case .switched:
                        if !pending.deleted {
                            shiftKeys[pending.id, default: ShiftKeyStats()].deleted += 1
                        }
                        pendingShiftKey = nil
                    case .passedInChinese:
                        pending.deleted = true
                        pendingShiftKey = pending
                    }
                }
                return
            }
            guard let category = key.category else { return }
            pendingRestore = nil

            if key.shifted, let keyCode = key.keyCode {
                readShiftedKey(key, app: app, keyCode: ShiftKey.key(forKeyCode: keyCode)?.keyCode ?? keyCode)
                return
            }
            pendingShiftKey = nil

            guard category == ShiftKeyCategory.letter.rawValue, let source = key.current else { return }
            if let signature = fieldSignatures[app] ?? nil {
                fieldLetters[FieldKey(bundleIdentifier: app, signature: signature), default: [:]][source, default: 0] +=
                    1
            }
            if !fieldHasOwnRule, visit?.bundleIdentifier == app {
                visit?.letters[source, default: 0] += 1
            }
        }

        private mutating func readShiftedKey(_ key: KeyFields, app: String, keyCode: Int) {
            let id = ShiftKeyID(bundleIdentifier: app, keyCode: keyCode)
            if let pending = pendingShiftKey, pending.id == id, pending.kind == .passedInChinese, pending.deleted,
               key.mono - pending.mono <= thresholds.shiftRetypeMilliseconds
            {
                shiftKeys[id, default: ShiftKeyStats()].retyped += 1
                pendingShiftKey = nil
                return
            }

            if key.switchedToEnglish {
                shiftKeys[id, default: ShiftKeyStats()].switches += 1
                pendingShiftKey = PendingShiftKey(id: id, kind: .switched, mono: key.mono)
            } else if let source = key.current, !SlashCommandTracker.isKeyboardLayout(source) {
                shiftKeys[id, default: ShiftKeyStats()].chineseUses += 1
                pendingShiftKey = PendingShiftKey(id: id, kind: .passedInChinese, mono: key.mono)
            } else {
                // Typed in English after another key, so a delete is not of the first.
                pendingShiftKey = nil
            }
        }
    }

    // MARK: - Suggestions

    private func percent(_ part: Int, of whole: Int) -> String {
        "\(Int((Double(part) / Double(max(whole, 1)) * 100).rounded()))%"
    }

    private func ruleSuggestions(_ reader: Reader, current: CurrentRules) -> [RuleSuggestion] {
        func name(_ id: String) -> String {
            current.inputSourceNames[id] ?? id
        }
        func appName(_ bundle: String) -> String {
            reader.applicationNames[bundle] ?? bundle
        }

        var result: [RuleSuggestion] = []
        for (scope, stats) in reader.scopes.sorted(by: { $0.key < $1.key }) {
            guard
                stats.visits > 0,
                let top = stats.corrections.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
                top.value >= thresholds.minimumCorrections,
                Double(top.value) / Double(stats.visits) >= thresholds.correctionShare
            else { continue }
            let letters = stats.letters.values.reduce(0, +)
            let topLetters = stats.letters[top.key] ?? 0
            guard Double(topLetters) / Double(max(letters, 1)) >= thresholds.correctedLetterShare else { continue }

            let corrected = "\(top.value) 次一进来就改成了 \(name(top.key))（\(percent(top.value, of: stats.visits))）"
            let typed = "打的字母 \(percent(topLetters, of: letters)) 是在 \(name(top.key)) 下打的"

            switch scope {
            case let .app(bundle):
                let target = current.target(for: bundle)
                guard !reader.terminals.contains(bundle), target != top.key else { continue }
                result.append(
                    RuleSuggestion(
                        id: "app:\(bundle)=\(top.key)",
                        title: "\(appName(bundle)) 默认用 \(name(top.key))",
                        evidence: "最近进入 \(appName(bundle)) 并打字 \(stats.visits) 次，\(corrected)；\(typed)。"
                            + "现在的规则是 \(target.map(name) ?? "未设置")。",
                        action: .setAppRule(
                            bundleIdentifier: bundle,
                            applicationName: appName(bundle),
                            inputSourceID: top.key
                        )
                    )
                )
            case let .command(key):
                let command = reader.commandNames[key] ?? key
                let target = current.target(forCandidates: stats.candidates, in: stats.bundleIdentifier)
                guard target != top.key else { continue }
                let terminal = stats.bundleIdentifier.map { appName($0) + " 里" } ?? "终端里"
                result.append(
                    RuleSuggestion(
                        id: "command:\(key)=\(top.key)",
                        title: "终端里的 \(command) 用 \(name(top.key))",
                        evidence: "最近在 \(terminal)运行 \(command) 并打字 \(stats.visits) 次，\(corrected)；\(typed)。"
                            + "现在用的是 \(target.map(name) ?? "未设置")。",
                        action: .setCommandRule(command: command, inputSourceID: top.key)
                    )
                )
            }
        }
        return result
    }

    private func fieldSuggestions(_ reader: Reader, current: CurrentRules) -> [RuleSuggestion] {
        func name(_ id: String) -> String {
            current.inputSourceNames[id] ?? id
        }
        func appName(_ bundle: String) -> String {
            reader.applicationNames[bundle] ?? bundle
        }

        var result: [RuleSuggestion] = []
        let sorted = reader.fieldLetters.sorted {
            "\($0.key.bundleIdentifier)\($0.key.signature.descriptor ?? "")"
                < "\($1.key.bundleIdentifier)\($1.key.signature.descriptor ?? "")"
        }
        for (key, counts) in sorted {
            let total = counts.values.reduce(0, +)
            guard total >= thresholds.minimumFieldLetters,
                  let top = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) }),
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
                    evidence: "在这个输入框里敲了 \(total) 个字母键，\(top.value) 个（\(percent(top.value, of: total))）是在 \(name(top.key)) 下敲的；"
                        + "App 默认是 \(current.target(for: key.bundleIdentifier).map(name) ?? "未设置")。",
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

    /// Where a change is made: in the one application that had nearly all of
    /// the mistakes, or everywhere.
    private func scope<Value>(
        of counts: [String: Value],
        mistakes: (Value) -> Int
    ) -> String? {
        let total = counts.values.map(mistakes).reduce(0, +)
        guard total > 0,
              let top = counts.max(by: { (mistakes($0.value), $1.key) < (mistakes($1.value), $0.key) }),
              Double(mistakes(top.value)) / Double(total) >= thresholds.singleApplicationShare
        else { return nil }
        return top.key
    }

    private func shiftSuggestions(_ reader: Reader, current: CurrentRules) -> [RuleSuggestion] {
        func appName(_ bundle: String) -> String {
            reader.applicationNames[bundle] ?? bundle
        }
        func place(_ bundle: String?) -> String {
            bundle.map { "在 \(appName($0)) 里" } ?? "在各个 App 里"
        }
        func scopeID(_ bundle: String?) -> String {
            bundle ?? "global"
        }
        func titleSuffix(_ bundle: String?) -> String {
            bundle.map { "（\(appName($0))）" } ?? ""
        }

        var result: [RuleSuggestion] = []
        let byKey = Dictionary(grouping: reader.shiftKeys, by: \.key.keyCode)
        for keyCode in byKey.keys.sorted() {
            let perApp = Dictionary(uniqueKeysWithValues: byKey[keyCode]!.map { ($0.key.bundleIdentifier, $0.value) })
            let label = ShiftKey.label(forKeyCode: keyCode)
            let category = ShiftKey.key(forKeyCode: keyCode)?.category ?? .symbol

            func sum(_ bundle: String?, _ value: (ShiftKeyStats) -> Int) -> Int {
                if let bundle {
                    return perApp[bundle].map(value) ?? 0
                }
                return perApp.values.map(value).reduce(0, +)
            }

            // Typed in Chinese, deleted and typed again: it should switch.
            let enableIn = scope(of: perApp, mistakes: \.retyped)
            let retyped = sum(enableIn, \.retyped)
            let chineseUses = sum(enableIn, \.chineseUses)
            let enableOptions = current.shiftOptions(for: enableIn)
            if retyped >= thresholds.minimumShiftMistakes,
               Double(retyped) / Double(max(chineseUses, 1)) >= thresholds.shiftEnableShare,
               !enableOptions.switches(keyCode: keyCode, category: category),
               // An application where Shift was turned off stays off.
               !(enableIn != nil && current.shiftAppRules[enableIn!]?.switchesNothing == true)
            {
                result.append(
                    RuleSuggestion(
                        id: "shiftKey:\(scopeID(enableIn)):\(keyCode)=on",
                        title: "\(label) 切到英文再打\(titleSuffix(enableIn))",
                        evidence: "最近\(place(enableIn))用中文输入法按了 \(chineseUses) 次 \(label)，"
                            + "有 \(retyped) 次（\(percent(retyped, of: chineseUses))）删掉后重新打了一遍。",
                        action: .setShiftKey(
                            bundleIdentifier: enableIn,
                            applicationName: enableIn.map(appName),
                            keyCode: keyCode,
                            enabled: true
                        )
                    )
                )
            }

            // Switched to English and deleted at once: it should not switch.
            let disableIn = scope(of: perApp, mistakes: \.deleted)
            let deleted = sum(disableIn, \.deleted)
            let switches = sum(disableIn, \.switches)
            if deleted >= thresholds.minimumShiftMistakes,
               Double(deleted) / Double(max(switches, 1)) >= thresholds.shiftDisableShare,
               current.shiftOptions(for: disableIn).switches(keyCode: keyCode, category: category)
            {
                result.append(
                    RuleSuggestion(
                        id: "shiftKey:\(scopeID(disableIn)):\(keyCode)=off",
                        title: "\(label) 不再切英文\(titleSuffix(disableIn))",
                        evidence: "最近\(place(disableIn)) \(label) 切到英文打出了 \(switches) 次，"
                            + "其中 \(deleted) 次（\(percent(deleted, of: switches))）马上被删掉了。",
                        action: .setShiftKey(
                            bundleIdentifier: disableIn,
                            applicationName: disableIn.map(appName),
                            keyCode: keyCode,
                            enabled: false
                        )
                    )
                )
            }
        }

        // Switched back to English just after letting go of Shift.
        let restoreIn = scope(of: reader.restores, mistakes: \.undone)
        let undone = restoreIn.map { reader.restores[$0]?.undone ?? 0 } ?? reader.restores.values.map(\.undone).reduce(
            0,
            +
        )
        let restores = restoreIn.map { reader.restores[$0]?.count ?? 0 } ?? reader.restores.values.map(\.count).reduce(
            0,
            +
        )
        if undone >= thresholds.minimumRestoreUndos,
           Double(undone) / Double(max(restores, 1)) >= thresholds.restoreUndoShare,
           current.shiftOptions(for: restoreIn).restoresOnRelease
        {
            result.append(
                RuleSuggestion(
                    id: "shiftRestore:\(scopeID(restoreIn))=off",
                    title: "松开 Shift 后不切回原输入法\(titleSuffix(restoreIn))",
                    evidence: "最近\(place(restoreIn))松开 Shift 后切回了 \(restores) 次，"
                        + "其中 \(undone) 次（\(percent(undone, of: restores))）马上又手动切回了英文。",
                    action: .setShiftRestore(
                        bundleIdentifier: restoreIn,
                        applicationName: restoreIn.map(appName),
                        enabled: false
                    )
                )
            )
        }
        return result
    }

    // MARK: - Lines

    private enum ParsedEvent { case appFocus, terminal, fieldFocus, manualSwitch }

    private enum QuickEvent {
        case key(KeyFields)
        case shiftRestore(app: String, mono: Double)
        case parse(ParsedEvent)
    }

    /// The fields of a key event, read from the bytes.
    private struct KeyFields {
        var app: String?
        var category: String?
        var current: String?
        var keyCode: Int?
        var mono: Double
        var shifted: Bool
        var isBackspace: Bool
        var switchedToEnglish: Bool

        init(_ buffer: UnsafeBufferPointer<UInt8>) {
            app = UsageAnalyzer.value(after: UsageAnalyzer.appKey, in: buffer)
            category = UsageAnalyzer.value(after: UsageAnalyzer.categoryKey, in: buffer)
            current = UsageAnalyzer.value(after: UsageAnalyzer.currentKey, in: buffer)
            keyCode = UsageAnalyzer.number(after: UsageAnalyzer.keyCodeKey, in: buffer).map { Int($0) }
            mono = UsageAnalyzer.number(after: UsageAnalyzer.monoKey, in: buffer) ?? 0
            shifted = UsageAnalyzer.contains(UsageAnalyzer.shiftedTrue, in: buffer)
            isBackspace = UsageAnalyzer.contains(UsageAnalyzer.backspaceKey, in: buffer)
            switchedToEnglish = UsageAnalyzer.contains(UsageAnalyzer.switchToEnglishDecision, in: buffer)
        }
    }

    private static let keyEvent = Array("\"e\":\"key\"".utf8)
    private static let switchEvent = Array("\"e\":\"switch\"".utf8)
    private static let shiftRestoreReason = Array("\"reason\":\"shiftRestore\"".utf8)
    private static let parsedEvents: [([UInt8], ParsedEvent)] = [
        (Array("\"e\":\"manualSwitch\"".utf8), .manualSwitch),
        (Array("\"e\":\"fieldFocus\"".utf8), .fieldFocus),
        (Array("\"e\":\"appFocus\"".utf8), .appFocus),
        (Array("\"e\":\"terminal\"".utf8), .terminal),
    ]
    private static let appKey = Array("\"app\":\"".utf8)
    private static let categoryKey = Array("\"category\":\"".utf8)
    private static let currentKey = Array("\"current\":\"".utf8)
    private static let keyCodeKey = Array("\"keyCode\":".utf8)
    private static let monoKey = Array("\"mono\":".utf8)
    private static let shiftedTrue = Array("\"shifted\":true".utf8)
    private static let backspaceKey = Array("\"key\":\"backspace\"".utf8)
    private static let switchToEnglishDecision = Array("\"shift\":\"switchToEnglish".utf8)

    private static func contains(_ needle: [UInt8], in buffer: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = buffer.baseAddress else { return false }
        return memmem(base, buffer.count, needle, needle.count) != nil
    }

    private static func start(after marker: [UInt8], in buffer: UnsafeBufferPointer<UInt8>) -> Int? {
        guard let base = buffer.baseAddress, let found = memmem(base, buffer.count, marker, marker.count) else {
            return nil
        }
        return base.distance(to: found.assumingMemoryBound(to: UInt8.self)) + marker.count
    }

    /// The string after a `"key":"` marker, for the plain identifiers the log
    /// writes there, which never contain quotes or escapes.
    private static func value(after marker: [UInt8], in buffer: UnsafeBufferPointer<UInt8>) -> String? {
        guard let start = start(after: marker, in: buffer),
              let end = buffer[start...].firstIndex(of: UInt8(ascii: "\""))
        else { return nil }
        return String(decoding: buffer[start..<end], as: UTF8.self)
    }

    /// The number after a `"key":` marker.
    private static func number(after marker: [UInt8], in buffer: UnsafeBufferPointer<UInt8>) -> Double? {
        guard let start = start(after: marker, in: buffer) else { return nil }
        let end = buffer[start...].firstIndex { $0 == UInt8(ascii: ",") || $0 == UInt8(ascii: "}") } ?? buffer.count
        return Double(String(decoding: buffer[start..<end], as: UTF8.self))
    }

    private static func signature(from value: Any?) -> FieldSignature? {
        guard let field = value as? [String: Any], let role = field["role"] as? String else { return nil }
        return FieldSignature(
            role: role,
            subrole: field["subrole"] as? String,
            identifier: field["identifier"] as? String,
            descriptor: field["descriptor"] as? String,
            ancestorRoles: field["ancestors"] as? [String] ?? [],
            isInWebArea: field["web"] as? Bool ?? false
        )
    }
}

public extension UsageAnalyzer {
    /// How many of the newest days of the log are read: habits change, and
    /// the log keeps more.
    static let analyzedDays = 14

    /// The lines of the newest days of the usage log in the default folder.
    @Sendable static func linesOfUsageLog() -> [String] {
        lines(inLogFiles: Array(JSONLUsageLogger().logFiles().suffix(analyzedDays)))
    }

    /// Reads the lines of the given log files, oldest first.
    static func lines(inLogFiles files: [URL]) -> [String] {
        files.flatMap { url -> [String] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").map(String.init)
        }
    }
}
