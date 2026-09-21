import XCTest
@testable import VibeStatistics

final class HistoryTests: XCTestCase {
    func sample(_ time: Double, _ value: Double, account: String = "a") -> UsageSnapshot {
        UsageSnapshot(provider: "codex", status: "ok", account: account, metrics: [UsageMetric(id: "weekly", title: "Weekly", value: value, unit: "%", kind: "quota")], collectedAt: time)
    }
    func testDailyLastValueDoesNotSumDuplicatesResetsOrRecharge() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let records = [sample(86410, 10), sample(86420, 100), sample(86420, 100), sample(3 * 86400, 90), sample(86430, 2, account: "b")]
        let result = History.daily(records, account: "a", metric: "weekly", since: .distantPast, calendar: calendar)
        XCTAssertEqual(result.map(\.value), [100, 90])
        XCTAssertEqual(result.count, 2) // Missing day remains absent.
    }
    func testRejectInvalidOrMissingData() {
        XCTAssertFalse(sample(100, .nan).isValid)
        XCTAssertFalse(sample(100, 101).isValid)
        XCTAssertTrue(sample(100, 0).isValid)
        XCTAssertFalse(UsageSnapshot.failure(.codex, code: "auth", message: "Expired").isValid)
    }
    func testMetricIdentityIsolatesCurrencies() {
        let s = UsageSnapshot(provider: "deepseek", status: "ok", account: "a", metrics: [UsageMetric(id: "CNY.balance", title: "Balance", value: 20, unit: "CNY", kind: "balance"), UsageMetric(id: "USD.balance", title: "Balance", value: 3, unit: "USD", kind: "balance")], collectedAt: 86410)
        XCTAssertEqual(History.daily([s], account: "a", metric: "USD.balance", since: .distantPast).first?.value, 3)
        XCTAssertTrue(History.daily([s], account: "b", metric: "USD.balance", since: .distantPast).isEmpty)
    }
    func testHomeTokenPeriodsUseMondayCalendarMonthAndLifetime() throws {        let zone = TimeZone(secondsFromGMT: 8 * 3600)!
        let formatter = ISO8601DateFormatter()
        let now = formatter.date(from: "2026-09-01T00:30:00+08:00")!
        let rows = [("2026-07-01", 1.0), ("2026-08-30", 10.0), ("2026-08-31", 100.0), ("2026-09-01", 1000.0), ("2026-09-02", 10000.0)]
            .map { LocalUsageDay(date: $0.0, input: $0.1, output: $0.1, cacheRead: 999, cacheWrite: nil) }
        let usage = LocalUsage(days: [], messageCount: 0, incomplete: false, scope: "test", allTimeDays: rows)
        XCTAssertEqual(usage.tokens(in: .week, now: now, timeZone: zone), 2200)
        XCTAssertEqual(usage.tokens(in: .month, now: now, timeZone: zone), 2000)
        XCTAssertEqual(usage.tokens(in: .allTime, now: now, timeZone: zone), 2222)
        let old = try JSONDecoder().decode(LocalUsage.self, from: Data(#"{"days":[],"messageCount":0,"incomplete":false,"scope":"old"}"#.utf8))
        XCTAssertNil(old.tokens(in: .allTime))
        XCTAssertNil(old.tokens(in: .week))
        let empty = LocalUsage(days: [], messageCount: 0, incomplete: false, scope: "test", allTimeDays: [])
        XCTAssertEqual(empty.tokens(in: .month), 0)
    }

    func quota(_ time: Double, _ value: Double, reset: Double? = nil, account: String = "a", metric: String = "weekly", unit: String = "%") -> UsageSnapshot {
        UsageSnapshot(provider: "codex", status: "ok", account: account, metrics: [UsageMetric(id: metric, title: "Quota", value: value, unit: unit, kind: "quota", resetAt: reset)], collectedAt: time)
    }
    func testConsumedSumsSameWindowDropsPerDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let records = [quota(86410, 90, reset: 100000), quota(86500, 80, reset: 100000), quota(86600, 70, reset: 100000),
                       quota(2 * 86410, 65, reset: 100000), quota(2 * 86410, 65, reset: 100000, account: "b")]
        let result = History.consumed(records, account: "a", metric: "weekly", since: .distantPast, calendar: calendar)
        XCTAssertEqual(result.map(\.value), [20])
        XCTAssertEqual(result.count, 1) // Days without an observed drop stay absent.
    }
    func testConsumedSkipsResetRefillAndRecharge() {
        let records = [quota(86410, 30, reset: 100000), quota(86500, 100, reset: 200000), quota(86600, 95, reset: 200000)]
        let result = History.consumed(records, account: "a", metric: "weekly", since: .distantPast)
        XCTAssertEqual(result.map(\.value), [5]) // The refill to 100 is not consumption; the new window drops 5.
    }
    func testConsumedSkipsDropAcrossWindowChange() {
        let records = [quota(86410, 20, reset: 100000), quota(86500, 90, reset: 200000)]
        XCTAssertTrue(History.consumed(records, account: "a", metric: "weekly", since: .distantPast).isEmpty)
    }
    func testConsumedToleratesEstimatedResetDrift() {
        let records = [quota(86410, 80, reset: 100000), quota(86500, 70, reset: 100500)]
        XCTAssertEqual(History.consumed(records, account: "a", metric: "weekly", since: .distantPast).map(\.value), [10])
    }
    func testConsumedCreditsWithoutResetSkipTopUp() {
        let records = [quota(86410, 500, metric: "userQuota", unit: "Credits"), quota(86500, 450, metric: "userQuota", unit: "Credits"),
                       quota(86600, 600, metric: "userQuota", unit: "Credits"), quota(86700, 550, metric: "userQuota", unit: "Credits")]
        let result = History.consumed(records, account: "a", metric: "userQuota", since: .distantPast)
        XCTAssertEqual(result.map(\.value), [100])
    }
    func testConsumedRespectsSinceBoundary() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let since = calendar.startOfDay(for: Date(timeIntervalSince1970: 2 * 86400))
        let records = [quota(172770, 90), quota(172790, 80), quota(2 * 86410, 70)]
        let result = History.consumed(records, account: "a", metric: "weekly", since: since, calendar: calendar)
        XCTAssertEqual(result.map(\.value), [10]) // The day-one drop is outside the window but seeds the day-two pair.
    }
}

final class GLMHistoryTests: XCTestCase {
    func row(_ time: Double, _ value: Double, reset: Double?) -> UsageSnapshot {
        UsageSnapshot(provider: "glm", status: "ok", account: "key", metrics: [UsageMetric(id: "q", title: "Quota", value: value, unit: "%", kind: "quota", resetAt: reset)], collectedAt: time)
    }
    func testMissingResetWindowChangeAndCollectionGapNeverCountAsConsumption() {
        for rows in [[row(100, 90, reset: nil), row(200, 80, reset: nil)],
                     [row(100, 90, reset: 10000), row(200, 80, reset: 10500)],
                     [row(100, 90, reset: 10000), row(5000, 80, reset: 10000)]] {
            XCTAssertTrue(History.consumed(rows, account: "key", metric: "q", since: .distantPast).isEmpty)
        }
        XCTAssertEqual(History.consumed([row(100, 90, reset: 10000), row(200, 80, reset: 10000)], account: "key", metric: "q", since: .distantPast).first?.value, 10)
    }
}
