import Foundation
import Darwin

public enum CodexLocator {
    public static func executable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let custom = environment["CODEX_EXECUTABLE"], !custom.isEmpty { candidates.append(custom) }
        // Finder-launched apps have a minimal PATH. Search both desktop distributions.
        for root in ["/Applications", "\(home)/Applications"] {
            for app in ["Codex.app", "ChatGPT.app"] {
                candidates += [
                    "\(root)/\(app)/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                    "\(root)/\(app)/Contents/Resources/codex-cli/bin/codex",
                    "\(root)/\(app)/Contents/Resources/codex"
                ]
            }
        }
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
}

/// A bounded read-only JSON-RPC exchange. No auth file access and no model calls.
public final class AccountClient {
    private let executable: URL?
    public init(executable: URL? = CodexLocator.executable()) { self.executable = executable }

    public func read(timeout: TimeInterval = 12) throws -> AccountQuota {
        guard let executable else { throw UsageError.codexMissing }
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        // Do not inherit an active agent's sandbox/turn identity into a new app server.
        for key in ["CODEX_THREAD_ID", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] { environment.removeValue(forKey: key) }
        process.environment = environment
        let mailbox = RPCMailbox()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            mailbox.append(data)
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            if process.processIdentifier > 0 { process.waitUntilExit() }
            try? output.fileHandleForReading.close()
        }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "codex-usage-macos", "version": "2.2.0"],
            "capabilities": ["experimentalApi": false]
        ]])
        _ = try mailbox.response(id: 1, deadline: deadline)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/rateLimits/read", "params": ["excludeResetCreditDetails": true]])
        return try AccountQuota.parse(result: mailbox.response(id: 2, deadline: deadline))
    }
}

private final class RPCMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private let signal = DispatchSemaphore(value: 0)
    private var pending = Data()
    private var messages: [[String: Any]] = []
    private var ended = false
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock(); signal.signal() }
        if data.isEmpty { ended = true; return }
        pending.append(data)
        // The usage response is small; reject runaway output instead of retaining it.
        if pending.count > 4_194_304 { ended = true; pending.removeAll(); return }
        while let index = pending.firstIndex(of: 10) {
            let line = pending[..<index]
            if let value = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
                messages.append(value)
                if messages.count > 100 { messages.removeFirst(messages.count - 100) }
            }
            pending.removeSubrange(...index)
        }
    }
    func response(id: Int, deadline: Date) throws -> [String: Any] {
        while true {
            lock.lock()
            let match = messages.firstIndex { ($0["id"] as? Int) == id }
            let message = match.map { messages.remove(at: $0) }
            let closed = ended
            lock.unlock()
            if let message {
                if message["error"] != nil {
                    // Server errors may contain account identifiers. Keep UI diagnostics generic.
                    throw UsageError.service("账户服务暂不可用，请确认 Codex 已登录，稍后重试。")
                }
                guard let result = message["result"] as? [String: Any] else { throw UsageError.quotaUnavailable }
                return result
            }
            if closed { throw UsageError.service("Codex 账户服务已断开，将自动重试。") }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0, signal.wait(timeout: .now() + remaining) == .success else { throw UsageError.timeout }
        }
    }
}
