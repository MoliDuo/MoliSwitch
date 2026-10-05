import AppKit
import MoliSwitchCore
import Carbon
import Darwin
import Foundation
import OSAKit

/// The program running in the foreground of the active terminal tab.
struct TerminalContext: Equatable, Sendable {
    let tty: String
    /// Names the program may be known by, most specific first.
    let candidates: [String]
    /// The title of the tab, kept when the program runs on another host and
    /// was found by its title.
    var remoteTitle: String? = nil

    var displayName: String {
        guard remoteTitle != nil, let first = candidates.first, let via = candidates.last, first != via else {
            return candidates.first ?? ""
        }
        return "\(first)（\(via)）"
    }

    /// The title changes all the time, for example with a spinner, so it does
    /// not make another context.
    static func == (lhs: TerminalContext, rhs: TerminalContext) -> Bool {
        lhs.tty == rhs.tty && lhs.candidates == rhs.candidates
    }
}

enum TerminalContextResult: Equatable, Sendable {
    case found(TerminalContext)
    /// The user did not allow MoliSwitch to read the terminal's tabs.
    case denied
    /// The tab could not be read right now, for example because no window is open.
    case unavailable
}

/// Reads the active tab of Terminal and iTerm2 through Apple Events and finds
/// the program in its foreground with sysctl, without starting any process
/// except tmux.
@MainActor
final class SystemTerminalContextProvider: TerminalContextProviding {
    private let inspector = TerminalTabInspector()

    func supportsTerminal(bundleIdentifier: String) -> Bool {
        TerminalTabInspector.supportsTerminal(bundleIdentifier: bundleIdentifier)
    }

    func foregroundContext(bundleIdentifier: String) -> TerminalContextResult {
        let inspector = inspector
        return inspector.queue.sync {
            inspector.foregroundContext(bundleIdentifier: bundleIdentifier)
        }
    }

    func foregroundContextInBackground(bundleIdentifier: String) async -> TerminalContextResult {
        let inspector = inspector
        return await withCheckedContinuation { continuation in
            inspector.queue.async {
                continuation.resume(returning: inspector.foregroundContext(bundleIdentifier: bundleIdentifier))
            }
        }
    }
}

/// Does the work of SystemTerminalContextProvider on its own serial queue. An
/// Apple Event to the terminal takes 25 ms and sometimes up to a second, and
/// the main thread also handles every key press, so the terminal is polled
/// from here. Everything but the queue is only touched on the queue.
private final class TerminalTabInspector: @unchecked Sendable {
    /// Statements returning the tty and the title of the active tab.
    private static let ttyScripts: [String: String] = [
        "com.apple.Terminal": "tell selected tab of front window to return {tty, custom title}",
        "com.googlecode.iterm2": "tell current session of current window to return {tty, name}",
    ]

    static func supportsTerminal(bundleIdentifier: String) -> Bool {
        ttyScripts[bundleIdentifier] != nil
    }

    let queue = DispatchQueue(label: "com.moli.MoliSwitch.terminal", qos: .userInitiated)

    /// A language instance of its own, so scripts can run off the main thread.
    private lazy var languageInstance: OSALanguageInstance? = OSALanguage(forName: "AppleScript")
        .map { OSALanguageInstance(language: $0) }
    private var compiledScripts: [String: OSAScript] = [:]
    private var pendingConsent: Set<String> = []
    private var programCache: [String: ForegroundProgram] = [:]

    func foregroundContext(bundleIdentifier: String) -> TerminalContextResult {
        dispatchPrecondition(condition: .onQueue(queue))

        switch Self.determinePermission(for: bundleIdentifier, askUserIfNeeded: false) {
        case noErr:
            break
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            requestConsent(for: bundleIdentifier)
            return .unavailable
        default:
            return .unavailable
        }

        guard let (tty, title) = activeTab(bundleIdentifier: bundleIdentifier) else {
            return .unavailable
        }
        guard let program = foregroundProgram(onTTY: tty) else {
            return .unavailable
        }

        if program.candidates.contains("tmux"),
           let pane = tmuxPaneTTY(clientTTY: tty, client: program),
           let paneProgram = foregroundProgram(onTTY: pane)
        {
            // A "tmux" rule still applies to panes whose program has no rule.
            return .found(TerminalContext(tty: pane, candidates: paneProgram.candidates + ["tmux"]))
        }

        // Over ssh the program is on the other host; its title may name it.
        if RemoteTitleParser.isRemoteLogin(program.candidates), let title {
            let remote = RemoteTitleParser.candidates(fromTitle: title)
            if !remote.isEmpty {
                return .found(TerminalContext(tty: tty, candidates: remote + program.candidates, remoteTitle: title))
            }
        }

        return .found(TerminalContext(tty: tty, candidates: program.candidates))
    }

    // MARK: - Apple Events

    private static func determinePermission(
        for bundleIdentifier: String,
        askUserIfNeeded: Bool
    ) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            AEEventClass(kAECoreSuite),
            AEEventID(kAEGetData),
            askUserIfNeeded
        )
    }

    /// Asks once, off this queue: the system prompt blocks the caller until the
    /// user answers.
    private func requestConsent(for bundleIdentifier: String) {
        guard pendingConsent.insert(bundleIdentifier).inserted else { return }

        Task.detached { [self] in
            _ = Self.determinePermission(for: bundleIdentifier, askUserIfNeeded: true)
            queue.async { self.pendingConsent.remove(bundleIdentifier) }
        }
    }

    private func activeTab(bundleIdentifier: String) -> (tty: String, title: String?)? {
        guard let script = compiledScript(for: bundleIdentifier) else { return nil }

        var error: NSDictionary?
        let start = ContinuousClock.now
        let result = script.executeAndReturnError(&error)
        let elapsed = Diagnostics.milliseconds(since: start)
        Diagnostics.record(.terminal, .debug, "active tab of \(bundleIdentifier) asked in \(elapsed) ms")
        let tty = result?.numberOfItems ?? 0 > 0 ? result?.atIndex(1)?.stringValue : result?.stringValue
        guard error == nil, let tty, tty.hasPrefix("/dev/") else {
            Diagnostics.record(
                .terminal, .error,
                "active tab of \(bundleIdentifier) unavailable: \(error?[NSAppleScript.errorMessage] as? String ?? "no tty in result"), \(elapsed) ms"
            )
            return nil
        }
        let title = result?.numberOfItems ?? 0 > 1 ? result?.atIndex(2)?.stringValue : nil
        return (tty, title)
    }

    private func compiledScript(for bundleIdentifier: String) -> OSAScript? {
        if let script = compiledScripts[bundleIdentifier] {
            return script
        }
        guard let expression = Self.ttyScripts[bundleIdentifier], let languageInstance else { return nil }

        let source = """
            with timeout of 1 second
                tell application id "\(bundleIdentifier)"
                    \(expression)
                end tell
            end timeout
            """
        let script = OSAScript(source: source, from: nil, languageInstance: languageInstance, using: [])

        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { return nil }
        compiledScripts[bundleIdentifier] = script
        return script
    }

    // MARK: - Processes

    private struct ForegroundProgram {
        let pid: pid_t
        let candidates: [String]
        let executablePath: String?
        let arguments: [String]
    }

    private func foregroundProgram(onTTY tty: String) -> ForegroundProgram? {
        guard let process = Self.foregroundProcess(onTTY: tty) else { return nil }

        // A running program keeps its path and arguments, so they are read once
        // per program instead of on every poll.
        if let cached = programCache[tty], cached.pid == process.pid {
            return cached
        }

        let executablePath = Self.executablePath(of: process.pid)
        let arguments = Self.arguments(of: process.pid)
        let program = ForegroundProgram(
            pid: process.pid,
            candidates: ForegroundProgramNames.candidates(
                processName: process.name,
                executablePath: executablePath,
                arguments: arguments
            ),
            executablePath: executablePath,
            arguments: arguments
        )

        if programCache.count > 32 {
            programCache.removeAll()
        }
        programCache[tty] = program
        return program
    }

    /// The leader of the foreground process group of a terminal device.
    private static func foregroundProcess(onTTY tty: String) -> (pid: pid_t, name: String)? {
        var status = stat()
        guard stat(tty, &status) == 0 else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(status.st_rdev)]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        // Leave room for processes started between the two calls.
        let stride = MemoryLayout<kinfo_proc>.stride
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 8)
        size = processes.count * stride
        guard sysctl(&mib, u_int(mib.count), &processes, &size, nil, 0) == 0 else {
            return nil
        }

        let foreground = processes.prefix(size / stride).filter {
            $0.kp_eproc.e_tpgid > 0
                && $0.kp_eproc.e_pgid == $0.kp_eproc.e_tpgid
                && $0.kp_proc.p_stat != SZOMB
        }
        guard
            let process = foreground.first(where: { $0.kp_proc.p_pid == $0.kp_eproc.e_pgid })
                ?? foreground.min(by: { $0.kp_proc.p_pid < $1.kp_proc.p_pid })
        else {
            return nil
        }

        let name = withUnsafeBytes(of: process.kp_proc.p_comm) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return (process.kp_proc.p_pid, name)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static let argumentBufferSize: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctl(&mib, 2, &value, &size, nil, 0) == 0, value > 0 else {
            return 256 * 1024
        }
        return Int(value)
    }()

    /// argv of a process, read with KERN_PROCARGS2: argc, the executable path,
    /// padding, then the arguments, all separated by NUL bytes.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var buffer = [UInt8](repeating: 0, count: argumentBufferSize)
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return []
        }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    // MARK: - tmux

    /// The terminal device of the pane that the tmux client on `clientTTY` shows.
    private func tmuxPaneTTY(clientTTY: String, client: ForegroundProgram) -> String? {
        guard let executablePath = client.executablePath else { return nil }

        let arguments = ForegroundProgramNames.tmuxServerArguments(client.arguments)
            + ["display-message", "-p", "-c", clientTTY, "#{pane_tty}"]
        guard let output = Self.run(executablePath, arguments: arguments, timeout: 0.5) else {
            return nil
        }

        let pane = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return pane.hasPrefix("/dev/") ? pane : nil
    }

    private static func run(_ executablePath: String, arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

/// Names under which a terminal program can be matched by a command rule.
enum ForegroundProgramNames {
    /// Programs that run a script named by their first argument.
    private static let interpreters: Set<String> = [
        "node", "bun", "deno", "ruby", "perl", "sh", "bash", "zsh", "fish",
    ]

    /// Options after which the next argument is code rather than a script.
    private static let inlineCodeOptions: Set<String> = ["-c", "-e", "--eval"]

    private static let scriptExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "py", "rb", "pl", "sh"]

    static func isInterpreter(_ name: String) -> Bool {
        let name = name.lowercased()
        return interpreters.contains(name) || name.hasPrefix("python")
    }

    /// Candidates, most specific first: the script an interpreter runs, the name
    /// the program was started as (argv[0], for example "claude" for a binary
    /// whose file is named after its version), the executable file and the
    /// process name.
    static func candidates(processName: String, executablePath: String?, arguments: [String]) -> [String] {
        var names: [String] = []

        func add(_ raw: String) {
            let name = CommandRuleSet.normalizedCommand(raw)
            if !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }

        let programNames = [arguments.first, executablePath, processName]
            .compactMap { $0 }
            .map(CommandRuleSet.normalizedCommand)
        if programNames.contains(where: isInterpreter), let script = scriptArgument(arguments) {
            let name = CommandRuleSet.normalizedCommand(script)
            let url = URL(fileURLWithPath: name)
            if scriptExtensions.contains(url.pathExtension.lowercased()) {
                add(url.deletingPathExtension().lastPathComponent)
            }
            add(name)
        }

        for name in programNames {
            add(name)
        }
        return names
    }

    private static func scriptArgument(_ arguments: [String]) -> String? {
        for argument in arguments.dropFirst() {
            if inlineCodeOptions.contains(argument) {
                return nil
            }
            if argument.hasPrefix("-") {
                continue
            }
            return argument.contains(where: \.isWhitespace) ? nil : argument
        }
        return nil
    }

    /// The -L and -S options of a tmux client, so a query reaches the same server.
    static func tmuxServerArguments(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "-L" || argument == "-S", index + 1 < arguments.count {
                result += [argument, arguments[index + 1]]
                index += 2
                continue
            }
            if argument.hasPrefix("-L") || argument.hasPrefix("-S"), argument.count > 2 {
                result.append(argument)
            }
            index += 1
        }
        return result
    }
}
