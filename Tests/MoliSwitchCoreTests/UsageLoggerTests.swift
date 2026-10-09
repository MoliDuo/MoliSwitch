import Foundation
import XCTest
@testable import MoliSwitchCore

final class UsageLoggerTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MoliSwitchUsageTests-" + UUID().uuidString, isDirectory: true)
    }

    private func lines(of url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func testEventIsOneFlatJSONLine() throws {
        let event = UsageEvent(
            "switch",
            ["from": "a", "to": .optional(nil), "ok": true, "ms": 1.5, "n": 3],
            time: Date(timeIntervalSince1970: 0),
            mono: 12.5
        )
        let line = event.jsonLine()

        XCTAssertFalse(line.contains("\n"))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["e"] as? String, "switch")
        XCTAssertEqual(object["from"] as? String, "a")
        XCTAssertTrue(object["to"] is NSNull)
        XCTAssertEqual(object["ok"] as? Bool, true)
        XCTAssertEqual(object["mono"] as? Double, 12.5)
        XCTAssertEqual(object["n"] as? Int, 3)
        XCTAssertNotNil(object["t"] as? String)
    }

    func testReservedKeysWinOverFields() throws {
        let line = UsageEvent("real", ["e": "fake", "t": "fake"]).jsonLine()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["e"] as? String, "real")
        XCTAssertNotEqual(object["t"] as? String, "fake")
    }

    func testTimestampKeepsMillisecondsAndOffset() {
        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        let text = UsageEvent.timestamp(Date(timeIntervalSince1970: 1.5), timeZone: zone)
        XCTAssertEqual(text, "1970-01-01T08:00:01.500+08:00")
    }

    func testTimestampDefaultsToSingaporeTime() {
        // 2026-01-01 00:00 UTC. Singapore was UTC+7:30 before 1982, so use a recent date.
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        XCTAssertEqual(UsageEvent.timestamp(date), "2026-01-01T08:00:00.000+08:00")
    }

    func testDayStartsAtSingaporeMidnight() {
        // 2026-01-01 16:00 UTC is midnight in Singapore.
        let midnight = Date(timeIntervalSince1970: 1_767_225_600 + 16 * 3600)
        XCTAssertEqual(JSONLUsageLogger.day(of: midnight.addingTimeInterval(-1)), "2026-01-01")
        XCTAssertEqual(JSONLUsageLogger.day(of: midnight), "2026-01-02")
    }

    func testFlushWritesEveryEventInOrder() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = JSONLUsageLogger(directory: directory)

        logger.log(UsageEvent("one"))
        logger.log(UsageEvent("two"))
        logger.flush()

        let files = logger.logFiles()
        XCTAssertEqual(files.count, 1)
        let written = try lines(of: files[0])
        XCTAssertEqual(written.count, 2)
        XCTAssertTrue(written[0].contains("\"e\":\"one\""))
        XCTAssertTrue(written[1].contains("\"e\":\"two\""))
    }

    func testEventsAreSplitIntoOneFilePerDay() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = JSONLUsageLogger(directory: directory)
        let day: TimeInterval = 86400 * 2

        logger.log(UsageEvent("old", time: Date(timeIntervalSinceNow: -day)))
        logger.log(UsageEvent("new"))
        logger.flush()

        XCTAssertEqual(logger.logFiles().count, 2)
    }

    func testFullBufferIsWrittenWithoutFlush() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = JSONLUsageLogger(directory: directory, flushInterval: 3600, maximumBuffered: 3)

        for index in 0..<3 {
            logger.log(UsageEvent("e\(index)"))
        }
        // flush() waits for the queue, so the batch of three is already out.
        logger.flush()
        XCTAssertEqual(try lines(of: logger.logFiles()[0]).count, 3)
    }

    func testDisabledLoggerWritesNothing() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = JSONLUsageLogger(directory: directory, isEnabled: false)

        logger.log(UsageEvent("ignored"))
        logger.flush()
        XCTAssertTrue(logger.logFiles().isEmpty)

        logger.isEnabled = true
        logger.log(UsageEvent("kept"))
        logger.flush()
        XCTAssertEqual(logger.logFiles().count, 1)
    }

    func testClearRemovesFilesAndPendingEvents() {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = JSONLUsageLogger(directory: directory, flushInterval: 3600)

        logger.log(UsageEvent("written"))
        logger.flush()
        logger.log(UsageEvent("pending"))
        logger.clear()
        logger.flush()

        XCTAssertTrue(logger.logFiles().isEmpty)
    }

    func testOldFilesAreRemovedAtStart() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appendingPathComponent("usage-2020-01-01.jsonl")
        let other = directory.appendingPathComponent("notes.txt")
        try "x\n".write(to: old, atomically: true, encoding: .utf8)
        try "x\n".write(to: other, atomically: true, encoding: .utf8)

        let logger = JSONLUsageLogger(directory: directory, retentionDays: 30)
        logger.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}
