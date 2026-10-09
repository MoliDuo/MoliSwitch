import Foundation

/// Receives the events of the usage log. Safe to call from any thread.
public protocol UsageLogging: AnyObject, Sendable {
    var isEnabled: Bool { get set }
    func log(_ event: UsageEvent)
    /// Writes what is still held in memory.
    func flush()
}

public final class NullUsageLogger: UsageLogging {
    public var isEnabled: Bool {
        get { false }
        set {}
    }

    public init() {}

    public func log(_ event: UsageEvent) {}
    public func flush() {}
}

/// Appends events to a JSON Lines file per day, usage-YYYY-MM-DD.jsonl, so a
/// day or two of use can be handed over for analysis.
///
/// Writing happens on a background queue and in batches, so logging a key
/// press never waits for the disk.
public final class JSONLUsageLogger: UsageLogging, @unchecked Sendable {
    public static let filePrefix = "usage-"
    public static let fileExtension = "jsonl"

    public let directory: URL

    private let retentionDays: Int
    private let flushInterval: TimeInterval
    private let maximumBuffered: Int
    private let queue = DispatchQueue(label: "com.moli.MoliSwitch.usage-log", qos: .utility)
    private let lock = NSLock()
    private var enabled: Bool

    // Confined to queue.
    private var buffer: [(day: String, line: String)] = []
    private var flushScheduled = false

    public init(
        directory: URL = JSONLUsageLogger.defaultDirectory(),
        isEnabled: Bool = true,
        retentionDays: Int = 30,
        flushInterval: TimeInterval = 1,
        maximumBuffered: Int = 50
    ) {
        self.directory = directory
        self.enabled = isEnabled
        self.retentionDays = retentionDays
        self.flushInterval = flushInterval
        self.maximumBuffered = maximumBuffered
        queue.async { [self] in
            removeExpiredFiles()
        }
    }

    public static func defaultDirectory(appName: String = "MoliSwitch") -> URL {
        JSONFileStore<AppRule>.applicationSupportDirectory(appName: appName)
            .appendingPathComponent("usage", isDirectory: true)
    }

    public var isEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return enabled
        }
        set {
            lock.lock()
            enabled = newValue
            lock.unlock()
        }
    }

    public func log(_ event: UsageEvent) {
        guard isEnabled else { return }

        let day = Self.day(of: event.time)
        let line = event.jsonLine()
        queue.async { [self] in
            buffer.append((day, line))
            if buffer.count >= maximumBuffered {
                writeBuffer()
            } else if !flushScheduled {
                flushScheduled = true
                queue.asyncAfter(deadline: .now() + flushInterval) { [self] in
                    writeBuffer()
                }
            }
        }
    }

    public func flush() {
        queue.sync { writeBuffer() }
    }

    /// Deletes every day's file, and what was not written yet.
    public func clear() {
        queue.sync {
            buffer.removeAll()
            for url in logFiles() {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// The files written so far, oldest first.
    public func logFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter {
                $0.lastPathComponent.hasPrefix(Self.filePrefix)
                    && $0.pathExtension == Self.fileExtension
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Writing

    private func writeBuffer() {
        flushScheduled = false
        guard !buffer.isEmpty else { return }

        let pending = buffer
        buffer.removeAll(keepingCapacity: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return
        }

        var linesByDay: [String: String] = [:]
        for entry in pending {
            linesByDay[entry.day, default: ""] += entry.line + "\n"
        }

        for (day, text) in linesByDay {
            let url = fileURL(forDay: day)
            guard let data = text.data(using: .utf8) else { continue }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { continue }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func fileURL(forDay day: String) -> URL {
        directory.appendingPathComponent(Self.filePrefix + day + "." + Self.fileExtension)
    }

    private func removeExpiredFiles() {
        guard retentionDays > 0 else { return }
        let calendar = MoliTime.calendar
        guard let limit = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        let oldestDay = Self.day(of: limit)

        for url in logFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            let day = String(name.dropFirst(Self.filePrefix.count))
            if day < oldestDay {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// YYYY-MM-DD in Singapore time.
    static func day(of date: Date) -> String {
        let parts = MoliTime.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
