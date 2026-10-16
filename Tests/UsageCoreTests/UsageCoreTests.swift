import Foundation
import Testing
@testable import UsageCore

@Suite(.serialized)
final class UsageCoreTests {
    private var folder: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: folder) }
    private func event(_ kind: String = "token_count", total: Int? = nil, at: Date? = nil,
                       turn: String? = nil, last: Int? = nil) -> Data {
        var payload: [String: Any] = ["type": kind]
        if let turn { payload["turn_id"] = turn }
        if let total {
            var info: [String: Any] = ["total_token_usage": ["total_tokens": total]]
            if let last { info["last_token_usage"] = ["total_tokens": last] }
            payload["info"] = info
        }
        let stamp = ISO8601DateFormatter().string(from: at ?? now)
        let value: [String: Any] = ["type": "event_msg", "timestamp": stamp, "payload": payload]
        var data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        // Match Codex's stable outer envelope order, with nested payload type after outer type.
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        data = Data("{\"timestamp\":\"\(stamp)\",\"type\":\"event_msg\",\"payload\":".utf8)
        data.append(payloadData); data.append(contentsOf: [125, 10])
        return data
    }
    private func write(_ data: Data, name: String = "session.jsonl") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd(); try handle.write(contentsOf: data); try handle.close()
    }

    @Test func testRolling24HoursUsesDeltasAndIgnoresDuplicateSnapshots() throws {
        let url = try write(event(total: 1000, at: now.addingTimeInterval(-90000)) + event(total: 1300, at: now.addingTimeInterval(-100)) + event(total: 1300, at: now.addingTimeInterval(-50)) + event(total: 1500))
        let reader = SessionReader(url: url)
        try reader.poll(now: now)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 500)
        expectTrue(reader.recent(now: now.addingTimeInterval(86401)).isEmpty)
    }
    @Test func testPartialLineRetriedAndIncrementalOffsetStable() throws {
        let tail = event(total: 80)
        let url = try write(event(total: 42) + tail.prefix(20))
        let reader = SessionReader(url: url)
        try reader.poll(now: now)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 42)
        try append(Data(tail.dropFirst(20)), to: url)
        try reader.poll(now: now); try reader.poll(now: now)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 80)
        expectEqual(reader.offset, UInt64(try Data(contentsOf: url).count))
    }
    @Test func testTruncationResetsCountersAndTaskLifecycle() throws {
        let url = try write(event("task_started", turn: "a") + event(total: 10000))
        let reader = SessionReader(url: url)
        try reader.poll(now: now)
        try event(total: 7).write(to: url)
        try reader.poll(now: now)
        expectFalse(reader.running)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 7)
    }
    @Test func testLifecycleIgnoresOtherTurnCompletion() throws {
        let url = try write(event("task_started", turn: "a"))
        let reader = SessionReader(url: url)
        try reader.poll(now: now); expectTrue(reader.running)
        try append(event("task_complete", turn: "b"), to: url)
        try reader.poll(now: now); expectTrue(reader.running)
        try append(event("turn_aborted", turn: "a"), to: url)
        try reader.poll(now: now); expectFalse(reader.running)
    }
    @Test func testCounterResetUsesLastUsage() throws {
        let url = try write(event(total: 500) + event(total: 20, last: 12))
        let reader = SessionReader(url: url); try reader.poll(now: now)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 512)
    }
    @Test func testCompletionWithNullTurnIDStopsRunningTask() throws {
        let url = try write(event("task_started", turn: "a"))
        let reader = SessionReader(url: url)
        try reader.poll(now: now)
        try append(Data("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":null}}\n".utf8), to: url)
        try reader.poll(now: now)
        expectFalse(reader.running)
    }
    @Test func testLargeUnrelatedLinesAreSkippedAcrossChunks() throws {
        let giant = Data(("{\"type\":\"response_item\",\"payload\":{\"token_count\":\"" + String(repeating: "x", count: 2_000_000) + "\"}}\n").utf8)
        expectNil(SessionReader.eventKind(giant))
        let url = try write(giant + event(total: 99))
        let reader = SessionReader(url: url); try reader.poll(now: now)
        expectEqual(reader.recent(now: now).reduce(0) { $0 + $1.delta }, 99)
    }
    @Test func testMetadataExtractsIDWithoutDecodingInstructions() throws {
        let id = "01234567-89ab-cdef-0123-456789abcdef"
        let meta = Data(("{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"instructions\":\"" + String(repeating: "x", count: 20_000) + "\"}}\n").utf8)
        let reader = SessionReader(url: try write(meta + event(total: 7)))
        try reader.poll(now: now)
        expectEqual(reader.sessionID, id)
    }
    @Test func testMalformedEventDoesNotBlockNextEvent() throws {
        let reader = SessionReader(url: try write(Data("{broken}\n".utf8) + event(total: 10)))
        try reader.poll(now: now)
        expectEqual(reader.recent(now: now).count, 1)
    }
    @Test func testForkHistoryIsDeduplicatedAcrossActiveAndArchive() throws {
        let history = event(total: 100)
        _ = try write(history, name: "sessions/a.jsonl")
        _ = try write(history + event(total: 150), name: "archived_sessions/b.jsonl")
        let stats = try UsageScanner(home: folder).scan(now: now)
        expectEqual(stats.dailyTokens, 150)
        expectEqual(stats.sessionCount, 2)
    }
    @Test func testArchivedRunningTasksAreExcluded() throws {
        _ = try write(event("task_started", turn: "a"), name: "sessions/a.jsonl")
        _ = try write(event("task_started", turn: "b"), name: "archived_sessions/b.jsonl")
        expectEqual(try UsageScanner(home: folder).scan(now: Date()).runningCount, 1)
    }
    @Test func testStaleRunningTaskBecomesUncertain() throws {
        let url = try write(event("task_started", at: now.addingTimeInterval(-2000), turn: "a"), name: "sessions/a.jsonl")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-2000)], ofItemAtPath: url.path)
        let stats = try UsageScanner(home: folder).scan(now: now)
        expectEqual(stats.runningCount, 0); expectEqual(stats.uncertainCount, 1)
    }
    @Test func testRemovedSessionIsNotRetained() throws {
        let url = try write(event(total: 30), name: "sessions/a.jsonl")
        let scanner = UsageScanner(home: folder)
        expectEqual(try scanner.scan(now: now).dailyTokens, 30)
        try FileManager.default.removeItem(at: url)
        expectEqual(try scanner.scan(now: now).dailyTokens, 0)
    }
    @Test func testMissingDirectoriesAreValidEmptyState() throws {
        expectEqual(try UsageScanner(home: folder).scan(now: now).dailyTokens, 0)
    }
    @Test func testFutureEventsExcludedUntilTheirTime() throws {
        let reader = SessionReader(url: try write(event(total: 5, at: now.addingTimeInterval(60))))
        try reader.poll(now: now)
        expectTrue(reader.recent(now: now).isEmpty)
        expectEqual(reader.recent(now: now.addingTimeInterval(61)).first?.delta, 5)
    }
    @Test func testQuotaClampsButNeverGuessesWindowDuration() {
        expectEqual(QuotaWindow(usedPercent: 125, windowDurationMins: 300, resetsAt: nil).remaining(expectedMinutes: 300), 0)
        expectEqual(QuotaWindow(usedPercent: -5, windowDurationMins: 300, resetsAt: nil).remaining(expectedMinutes: 300), 100)
        expectNil(QuotaWindow(usedPercent: 25, windowDurationMins: nil, resetsAt: nil).remaining(expectedMinutes: 300))
        expectNil(QuotaWindow(usedPercent: 25, windowDurationMins: 60, resetsAt: nil).remaining(expectedMinutes: 300))
        expectNil(QuotaWindow(usedPercent: nil, windowDurationMins: 300, resetsAt: nil).remaining(expectedMinutes: 300))
    }
    @Test func testExpiredQuotaDoesNotDisplayAFutureResetTime() {
        let window = QuotaWindow(usedPercent: 12, windowDurationMins: 300, resetsAt: now.timeIntervalSince1970 - 1)
        expectNil(window.remaining(expectedMinutes: 300, now: now))
        expectEqual(window.resetLabel(now: now), "等待额度更新")
    }
    @Test func testSameDayResetDisplaysSpecific24HourTime() {
        let iso = ISO8601DateFormatter()
        let testNow = iso.date(from: "2026-10-16T01:00:00Z")!
        let reset = iso.date(from: "2026-10-16T06:05:00Z")!
        let window = QuotaWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: reset.timeIntervalSince1970)
        expectEqual(window.resetLabel(now: testNow, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "14:05 重置")
    }
    @Test func testFutureDayResetDisplaysDateAndSpecificTime() {
        let iso = ISO8601DateFormatter()
        let testNow = iso.date(from: "2026-10-16T01:00:00Z")!
        let reset = iso.date(from: "2026-10-22T06:05:00Z")!
        let window = QuotaWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: reset.timeIntervalSince1970)
        expectEqual(window.resetLabel(now: testNow, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "10月22日 14:05 重置")
    }
    @Test func testResetCalendarDayRespectsTimeZone() {
        let iso = ISO8601DateFormatter()
        let testNow = iso.date(from: "2026-10-16T15:50:00Z")!
        let reset = iso.date(from: "2026-10-16T16:05:00Z")!
        let window = QuotaWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: reset.timeIntervalSince1970)
        expectEqual(window.resetLabel(now: testNow, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "10月17日 00:05 重置")
        expectEqual(window.resetLabel(now: testNow, timeZone: TimeZone(secondsFromGMT: 0)!), "16:05 重置")
    }
    @Test func testNewYearAndUnavailableResetLabels() {
        let iso = ISO8601DateFormatter()
        let testNow = iso.date(from: "2026-12-31T15:50:00Z")!
        let reset = iso.date(from: "2026-12-31T16:05:00Z")!
        let window = QuotaWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: reset.timeIntervalSince1970)
        expectEqual(window.resetLabel(now: testNow, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "2027年1月1日 00:05 重置")
        expectEqual(QuotaWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: nil).resetLabel(), "重置时间未知")
        expectEqual(QuotaWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: .infinity).resetLabel(), "重置时间未知")
    }
    @Test func testMultiBucketQuotaTakesPrecedence() throws {
        let result: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 80, "windowDurationMins": 300]],
                                    "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 10, "windowDurationMins": 300]]]]
        expectEqual(try AccountQuota.parse(result: result).primary?.remaining(expectedMinutes: 300), 90)
    }
    @Test func testOtherModelQuotaNeverMasqueradesAsCodex() {
        let result: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 80]],
                                    "rateLimitsByLimitId": ["other": ["primary": ["usedPercent": 10]]]]
        expectThrows(try AccountQuota.parse(result: result))
    }
    @Test func testLocatorHonorsExplicitExecutableWithMinimalFinderPATH() throws {
        let executable = try server("exit 0\n")
        expectEqual(CodexLocator.executable(environment: ["PATH": "/usr/bin:/bin", "CODEX_EXECUTABLE": executable.path]), executable)
    }
    @Test func testMissingCodexHasUsefulError() {
        expectThrows(try AccountClient(executable: nil).read()) { error in
            expectTrue(error.localizedDescription.contains("未找到"))
        }
    }
    private func server(_ body: String) throws -> URL {
        let url = try write(Data(("#!/bin/sh\n" + body).utf8), name: "fake-codex")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    @Test func testAccountTransportWaitsForInitializeAndReadsSnapshot() throws {
        let script = """
        IFS= read -r request
        case "$request" in *'"initialize"'*) ;; *) exit 2;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r notification
        case "$notification" in *'"initialized"'*) ;; *) exit 3;; esac
        IFS= read -r request
        case "$request" in *'rateLimits'*) ;; *) exit 4;; esac
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":2000000000}}}}'
        while IFS= read -r ignored; do :; done
        """
        let quota = try AccountClient(executable: server(script)).read(timeout: 2)
        expectEqual(quota.primary?.remaining(expectedMinutes: 300, now: now), 90)
    }
    @Test func testAccountTransportTimeoutDoesNotHang() throws {
        let url = try server("while IFS= read -r ignored; do :; done\n")
        let started = Date()
        expectThrows(try AccountClient(executable: url).read(timeout: 0.15))
        expectLessThan(Date().timeIntervalSince(started), 2)
    }
    @Test func testAccountServiceFailureDoesNotExposeRawResponse() throws {
        let url = try server("IFS= read -r request\nprintf '%s\\n' '{\"id\":1,\"error\":{\"message\":\"private-account-id\"}}'\nwhile IFS= read -r ignored; do :; done\n")
        expectThrows(try AccountClient(executable: url).read(timeout: 1)) { error in
            expectFalse(error.localizedDescription.contains("private-account-id"))
        }
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value == nil, sourceLocation: sourceLocation) }
private func expectNotNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value != nil, sourceLocation: sourceLocation) }
private func expectLessThan<T: Comparable>(_ value: T, _ bound: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value < bound, sourceLocation: sourceLocation) }
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation, check: (Error) -> Void = { _ in }) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) }
    catch { check(error) }
}
