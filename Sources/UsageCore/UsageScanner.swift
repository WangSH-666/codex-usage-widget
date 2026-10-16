import Foundation

// Only byte prefixes are inspected for unrelated lines. Prompts, tools, images,
// and large session metadata are never deserialized or retained.
public final class SessionReader {
    public let url: URL
    public private(set) var offset: UInt64 = 0
    public private(set) var running = false
    public private(set) var activity: TimeInterval = 0
    public private(set) var sessionID: String
    private var turnID: String?
    private var previousTotal = 0
    private var contributions: [(time: TimeInterval, delta: Int, key: String)] = []
    private static let types = try! NSRegularExpression(pattern: #"(?<!\\)"type"\s*:\s*"([^"\\]+)""#)
    private static let ids = try! NSRegularExpression(pattern: #"(?<!\\)"(?:session_id|id)"\s*:\s*"([0-9a-fA-F-]{36})""#)
    private static let kinds: Set<String> = ["token_count", "task_started", "task_complete", "turn_aborted"]
    private static let iso = ISO8601DateFormatter()
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(url: URL) { self.url = url; sessionID = String(url.deletingPathExtension().lastPathComponent.suffix(36)) }

    public static func eventKind(_ data: Data) -> String? {
        let prefix = String(decoding: data.prefix(8192), as: UTF8.self)
        let ns = prefix as NSString
        let matches = types.matches(in: prefix, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else { return nil }
        let outer = ns.substring(with: first.range(at: 1))
        if outer == "session_meta" { return outer }
        guard outer == "event_msg", matches.count > 1 else { return nil }
        let kind = ns.substring(with: matches[1].range(at: 1))
        return kinds.contains(kind) ? kind : nil
    }

    public func poll(now: Date = Date()) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        if size < offset {
            offset = 0; previousTotal = 0; contributions.removeAll()
            running = false; activity = 0; turnID = nil
        }
        try handle.seek(toOffset: offset)
        var pending = Data()
        var skipped = false
        var cursor = offset
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            var start = chunk.startIndex
            while let newline = chunk[start...].firstIndex(of: 10) {
                let end = chunk.index(after: newline)
                if !skipped {
                    pending.append(chunk[start..<newline])
                    if pending.count <= 1_048_576 { consume(pending, now: now) }
                }
                cursor += UInt64(end - start)
                offset = cursor
                pending.removeAll(keepingCapacity: true)
                skipped = false
                start = end
            }
            let tail = chunk[start...]
            cursor += UInt64(tail.count)
            if !skipped {
                pending.append(tail)
                if pending.count > 1_048_576 { pending.removeAll(keepingCapacity: false); skipped = true }
            }
        }
        // offset advances only past complete lines; a partial event is retried next poll.
        contributions.removeAll { $0.time < now.timeIntervalSince1970 - 86400 }
    }

    private func consume(_ data: Data, now: Date) {
        guard let envelope = Self.eventKind(data) else { return }
        if envelope == "session_meta" {
            let prefix = String(decoding: data.prefix(8192), as: UTF8.self) as NSString
            if let match = Self.ids.firstMatch(in: prefix as String, range: NSRange(location: 0, length: prefix.length)) {
                sessionID = prefix.substring(with: match.range(at: 1))
            }
            return
        }
        guard let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              event["type"] as? String == "event_msg",
              let payload = event["payload"] as? [String: Any],
              let kind = payload["type"] as? String else { return }
        let stamp = event["timestamp"] as? String ?? ""
        let at = (Self.fractional.date(from: stamp) ?? Self.iso.date(from: stamp))?.timeIntervalSince1970 ?? 0
        activity = max(activity, at)
        switch kind {
        case "task_started": running = true; turnID = payload["turn_id"] as? String
        case "task_complete", "turn_aborted":
            let endingTurn = payload["turn_id"] as? String
            if endingTurn == nil || endingTurn == turnID { running = false }
        case "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let usage = info["total_token_usage"] as? [String: Any],
                  let total = usage["total_tokens"] as? Int, total >= 0 else { return }
            let last = info["last_token_usage"] as? [String: Any] ?? [:]
            let delta = total >= previousTotal ? total - previousTotal : max(0, last["total_tokens"] as? Int ?? 0)
            previousTotal = total
            if delta > 0, at >= now.timeIntervalSince1970 - 86400 {
                let signature = (try? JSONSerialization.data(withJSONObject: last, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
                contributions.append((at, delta, "\(stamp)|\(total)|\(signature)"))
            }
        default: break
        }
    }

    public func recent(now: Date) -> [(time: TimeInterval, delta: Int, key: String)] {
        let cutoff = now.timeIntervalSince1970 - 86400
        return contributions.filter { $0.time >= cutoff && $0.time <= now.timeIntervalSince1970 }
    }
}

/// Mutable reader state is protected by a lock; scans run off the main thread.
public final class UsageScanner: @unchecked Sendable {
    public let home: URL
    private let lock = NSLock()
    private var readers: [URL: SessionReader] = [:]
    public init(home: URL = defaultHome) { self.home = home }
    public static var defaultHome: URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
    public func scan(now: Date = Date()) throws -> UsageStats {
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        var paths: [(URL, Date, Bool)] = []
        for folder in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(folder)
            guard manager.fileExists(atPath: root.path) else { continue }
            var readFailed = false
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                     options: [.skipsHiddenFiles], errorHandler: { _, _ in readFailed = true; return true }) else { throw UsageError.logRead }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                paths.append((url, values.contentModificationDate ?? .distantPast, folder == "archived_sessions"))
            }
            if readFailed { throw UsageError.logRead }
        }
        paths.sort { $0.1 > $1.1 }
        let existing = Set(paths.map(\.0))
        readers = readers.filter { existing.contains($0.key) }
        let cutoff = now.addingTimeInterval(-86400)
        var tasks: [String: (TimeInterval, Bool, Bool)] = [:]
        var seen = Set<String>()
        var total = 0
        for (index, item) in paths.enumerated() {
            let (path, modified, archived) = item
            guard modified >= cutoff || index < 5 || readers[path] != nil else { continue }
            let reader = readers[path] ?? SessionReader(url: path)
            do { try reader.poll(now: now) }
            catch CocoaError.fileReadNoSuchFile { readers[path] = nil; continue }
            readers[path] = reader
            for entry in reader.recent(now: now) where seen.insert(entry.key).inserted { total += entry.delta }
            if !archived {
                let uncertain = reader.running && now.timeIntervalSince1970 - max(reader.activity, modified.timeIntervalSince1970) > 900
                if tasks[reader.sessionID] == nil || tasks[reader.sessionID]!.0 < reader.activity {
                    tasks[reader.sessionID] = (reader.activity, reader.running, uncertain)
                }
            }
        }
        return UsageStats(dailyTokens: total, runningCount: tasks.values.filter { $0.1 && !$0.2 }.count,
                          uncertainCount: tasks.values.filter { $0.1 && $0.2 }.count,
                          sessionCount: paths.count, scannedAt: now)
    }
}
