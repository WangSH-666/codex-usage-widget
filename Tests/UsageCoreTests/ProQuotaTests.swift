import Foundation
import Testing
@testable import UsageCore

@Suite struct ProQuotaTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func week(used: Double = 27, reset: Double = 1_800_600_000) -> [String: Any] {
        ["usedPercent": used, "windowDurationMins": 10080, "resetsAt": reset]
    }
    private func parse(_ snapshot: [String: Any]) throws -> AccountQuota {
        try AccountQuota.parse(result: ["rateLimitsByLimitId": ["codex": snapshot]], now: now)
    }

    @Test func proWithWeeklySecondaryUsesSingleRing() throws {
        let quota = try parse(["planType": "pro", "primary": NSNull(), "secondary": week()])
        #expect(quota.planType == "pro")
        #expect(quota.planLabel == "Pro")
        #expect(quota.isWeeklyOnly)
        #expect(quota.fiveHour == nil)
        #expect(quota.weekly?.remaining(expectedMinutes: 10080, now: now) == 73)
    }

    @Test func proWithWeeklyPrimaryUsesTheSameWeek() throws {
        let quota = try parse(["planType": "promax", "primary": week(), "secondary": NSNull()])
        #expect(quota.planLabel == "Pro Max")
        #expect(quota.isWeeklyOnly)
        #expect(quota.weekly == quota.primary)
        #expect(quota.fiveHour == nil)
    }

    @Test func proWithBothWindowsDoesNotHideReturnedFiveHours() throws {
        let quota = try parse(["planType": "pro", "primary": ["usedPercent": 12, "windowDurationMins": 300],
                               "secondary": week()])
        #expect(!quota.isWeeklyOnly)
        #expect(quota.fiveHour?.remaining(expectedMinutes: 300, now: now) == 88)
        #expect(quota.weekly != nil)
    }

    @Test func plusWithReversedSlotsUsesDurations() throws {
        let quota = try parse(["planType": "plus", "primary": week(),
                               "secondary": ["usedPercent": 12, "windowDurationMins": 300]])
        #expect(!quota.isWeeklyOnly)
        #expect(quota.fiveHour == quota.secondary)
        #expect(quota.weekly == quota.primary)
    }

    @Test func legacyWeeklyResponseNeedsNoPlanGuess() throws {
        let quota = try AccountQuota.parse(result: ["rateLimits": ["primary": week()]], now: now)
        #expect(quota.planType == nil)
        #expect(quota.isWeeklyOnly)
        let restored = try JSONDecoder().decode(AccountQuota.self, from: JSONEncoder().encode(quota))
        #expect(restored == quota)
    }

    @Test func unknownAndUnsupportedDurationsDoNotPretendToBeWeeklyOnly() throws {
        for primary in [["usedPercent": 0], ["usedPercent": 0, "windowDurationMins": 60]] {
            let quota = try parse(["planType": "pro", "primary": primary, "secondary": week()])
            #expect(!quota.isWeeklyOnly)
            #expect(quota.fiveHour == nil)
            #expect(quota.weekly != nil)
        }
    }

    @Test func expiredWeekKeepsGeometryButNeverInventsRemaining() throws {
        let quota = try parse(["planType": "pro", "secondary": week(reset: now.timeIntervalSince1970 - 1)])
        #expect(quota.isWeeklyOnly)
        #expect(quota.weekly?.remaining(expectedMinutes: 10080, now: now) == nil)
        #expect(quota.weekly?.resetLabel(now: now) == "等待额度更新")
    }

    @Test func planComesOnlyFromTheAuthoritativeCodexBucket() throws {
        let quota = try AccountQuota.parse(result: [
            "rateLimits": ["planType": "pro", "secondary": week()],
            "rateLimitsByLimitId": ["codex": ["planType": "plus", "primary": ["usedPercent": 0, "windowDurationMins": 300]],
                                    "other_model": ["planType": "pro", "secondary": week()]]
        ], now: now)
        #expect(quota.planType == "plus")
        #expect(!quota.isWeeklyOnly)
        #expect(quota.weekly == nil)
    }

    @Test func planAloneDoesNotFabricateQuota() {
        #expect(throws: UsageError.self) { try parse(["planType": "pro"]) }
    }

    @Test func weeklyEndpointsAndUnknownUsageRemainHonest() throws {
        for used in [0.0, 100.0] {
            let quota = try parse(["planType": "pro", "primary": week(used: used)])
            #expect(quota.isWeeklyOnly)
            #expect(quota.weekly?.remaining(expectedMinutes: 10080, now: now) == 100 - used)
        }
        let unknown = try parse(["planType": "pro", "primary": ["windowDurationMins": 10080]])
        #expect(unknown.isWeeklyOnly)
        #expect(unknown.weekly?.remaining(expectedMinutes: 10080, now: now) == nil)
    }
}
