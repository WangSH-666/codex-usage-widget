import AppKit
import UsageCore

if CommandLine.arguments.contains("--update-status") {
    Task {
        do {
            let release = try await UpdateClient().latest()
            let result: [String: String] = ["version": release.version, "page": release.pageURL.absoluteString,
                "download": release.downloadURL?.absoluteString ?? ""]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    dispatchMain()
}

// Demo mode must never fall through to the real log/account diagnostic path.
if (CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--demo-pro")) && CommandLine.arguments.contains("--snapshot") {
    fputs("Demo mode does not support real account snapshots. Use --demo --ui-check instead.\n", stderr)
    exit(2)
}

if CommandLine.arguments.contains("--snapshot") {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    struct Snapshot: Encodable {
        let version: String
        let stats: UsageStats?
        let quota: AccountQuota?
        let scanError: String?
        let accountError: String?
    }
    var stats: UsageStats?, quota: AccountQuota?
    var scanError: String?, accountError: String?
    do { stats = try UsageScanner().scan() } catch { scanError = error.localizedDescription }
    do { quota = try AccountClient().read() } catch { accountError = error.localizedDescription }
    let snapshot = Snapshot(version: "2.2.0", stats: stats, quota: quota, scanError: scanError, accountError: accountError)
    if let data = try? encoder.encode(snapshot) { print(String(decoding: data, as: UTF8.self)) }
    exit(scanError == nil && accountError == nil ? 0 : 1)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
