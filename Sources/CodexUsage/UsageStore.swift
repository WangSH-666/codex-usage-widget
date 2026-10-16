import AppKit
import Combine
import UsageCore

@MainActor final class UsageStore: ObservableObject {
    private let demoMode: Bool
    @Published private(set) var stats: UsageStats?
    @Published private(set) var quota: AccountQuota?
    @Published private(set) var scanError: String?
    @Published private(set) var accountError: String?
    @Published private(set) var scanning = false
    @Published private(set) var syncing = false
    @Published private(set) var now = Date()
    private let scanner = UsageScanner()
    private let scanQueue = DispatchQueue(label: "local.codexusage.scan", qos: .utility)
    private let accountQueue = DispatchQueue(label: "local.codexusage.account", qos: .utility)
    private var timer: AnyCancellable?
    private var nextScan = Date.distantPast
    private var nextAccount = Date.distantPast
    private var scanAgain = false
    private var accountAgain = false
    var interval = 30

    init(demoMode: Bool = CommandLine.arguments.contains("--demo")) {
        self.demoMode = demoMode
    }

    func start() {
        refresh()
        guard !demoMode else { return }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] date in
            guard let self else { return }
            self.now = date
            if date >= self.nextScan && !self.scanning { self.scan() }
            if date >= self.nextAccount && !self.syncing { self.syncAccount() }
        }
    }
    func refresh() {
        if demoMode {
            let sampleDate = ISO8601DateFormatter().date(from: "2026-10-16T10:00:00+08:00")!
            now = sampleDate
            stats = UsageStats(dailyTokens: 12_340_000, scannedAt: sampleDate)
            quota = AccountQuota(
                primary: QuotaWindow(usedPercent: 38, windowDurationMins: 300,
                                     resetsAt: sampleDate.addingTimeInterval(5 * 3600).timeIntervalSince1970),
                secondary: QuotaWindow(usedPercent: 27, windowDurationMins: 10080,
                                       resetsAt: sampleDate.addingTimeInterval(6 * 86400).timeIntervalSince1970),
                fetchedAt: sampleDate)
            return
        }
        if scanning { scanAgain = true } else { scan() }
        if syncing { accountAgain = true } else { syncAccount() }
    }
    private func scan() {
        scanning = true
        nextScan = Date().addingTimeInterval(TimeInterval(interval))
        let scanner = self.scanner
        scanQueue.async { [weak self] in
            let result = Result { try scanner.scan() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanning = false
                switch result {
                case .success(let value): self.stats = value; self.scanError = nil
                case .failure(let error): self.scanError = error.localizedDescription
                }
                if self.scanAgain { self.scanAgain = false; self.scan() }
            }
        }
    }
    private func syncAccount() {
        syncing = true
        accountQueue.async { [weak self] in
            let result = Result { try AccountClient().read() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.syncing = false
                switch result {
                case .success(let value): self.quota = value; self.accountError = nil
                case .failure(let error): self.accountError = error.localizedDescription
                    // A failed read can mean account sign-out or switching. Do not retain another account's quota.
                    self.quota = nil
                }
                self.nextAccount = Date().addingTimeInterval(self.accountError == nil ? 30 : 10)
                if self.accountAgain { self.accountAgain = false; self.syncAccount() }
            }
        }
    }
    var quotaIsStale: Bool { quota.map { now.timeIntervalSince($0.fetchedAt) > 90 } ?? false }
    var footer: String {
        if scanError != nil { return "读取失败 · 将自动重试" }
        guard let stats else { return "正在读取本机用量" }
        return "\(stats.runningCount) 个任务正在运行"
    }
    var syncLabel: String {
        if syncing && quota == nil { return "同步中" }
        if accountError != nil { return "额度离线" }
        if quotaIsStale { return "额度待更新" }
        return quota == nil ? "等待同步" : "已同步"
    }
}
