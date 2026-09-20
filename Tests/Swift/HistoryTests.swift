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
}
