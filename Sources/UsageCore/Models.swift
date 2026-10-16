import Foundation

public struct UsageStats: Codable, Equatable, Sendable {
    public var dailyTokens: Int
    public var runningCount: Int
    public var uncertainCount: Int
    public var sessionCount: Int
    public var scannedAt: Date
    public init(dailyTokens: Int = 0, runningCount: Int = 0, uncertainCount: Int = 0,
                sessionCount: Int = 0, scannedAt: Date = Date()) {
        self.dailyTokens = dailyTokens
        self.runningCount = runningCount
        self.uncertainCount = uncertainCount
        self.sessionCount = sessionCount
        self.scannedAt = scannedAt
    }
    public var millions: String { String(format: "%.2f", Double(dailyTokens) / 1_000_000) }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: TimeInterval?
    public init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: TimeInterval?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
    public func remaining(expectedMinutes: Int, now: Date = Date()) -> Double? {
        guard windowDurationMins == expectedMinutes, let usedPercent, usedPercent.isFinite,
              resetsAt.map({ $0 > now.timeIntervalSince1970 }) ?? true else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }
    public func resetLabel(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        guard let resetsAt, resetsAt.isFinite else { return "重置时间未知" }
        guard resetsAt > now.timeIntervalSince1970 else { return "等待额度更新" }
        let date = Date(timeIntervalSince1970: resetsAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "M月d日 HH:mm"
        } else {
            formatter.dateFormat = "yyyy年M月d日 HH:mm"
        }
        return formatter.string(from: date) + " 重置"
    }
}

public struct AccountQuota: Codable, Equatable, Sendable {
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let fetchedAt: Date
    public init(primary: QuotaWindow?, secondary: QuotaWindow?, fetchedAt: Date = Date()) {
        self.primary = primary
        self.secondary = secondary
        self.fetchedAt = fetchedAt
    }
    public static func parse(result: [String: Any], now: Date = Date()) throws -> AccountQuota {
        let buckets = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
        // A populated multi-bucket result is authoritative. Never pick another model's quota.
        let snapshot = buckets.isEmpty ? result["rateLimits"] as? [String: Any] : buckets["codex"] as? [String: Any]
        guard let snapshot else { throw UsageError.quotaUnavailable }
        func window(_ value: Any?) -> QuotaWindow? {
            guard let data = value as? [String: Any] else { return nil }
            return QuotaWindow(usedPercent: (data["usedPercent"] as? NSNumber)?.doubleValue,
                               windowDurationMins: data["windowDurationMins"] as? Int,
                               resetsAt: (data["resetsAt"] as? NSNumber)?.doubleValue)
        }
        let primary = window(snapshot["primary"])
        let secondary = window(snapshot["secondary"])
        guard primary != nil || secondary != nil else { throw UsageError.quotaUnavailable }
        return AccountQuota(primary: primary, secondary: secondary, fetchedAt: now)
    }
}

public enum UsageError: LocalizedError {
    case codexMissing, quotaUnavailable, timeout, service(String), logRead
    public var errorDescription: String? {
        switch self {
        case .codexMissing: return "未找到 Codex 内核，请安装并登录 Codex 或 ChatGPT。"
        case .quotaUnavailable: return "账户暂未返回 Codex 额度，请确认已登录并使用订阅账户。"
        case .timeout: return "账户同步超时，将自动重试。"
        case .service(let message): return message
        case .logRead: return "会话记录暂不可读，请检查 Codex 数据目录权限。"
        }
    }
}
