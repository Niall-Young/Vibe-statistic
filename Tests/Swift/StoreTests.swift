import XCTest
import SwiftData
@testable import VibeStatistics

actor FakeProvider: UsageProvider {
    var count = 0
    func fetch(_ agent: Agent, path: String, node: String, secret: String?) async -> UsageSnapshot {
        count += 1
        try? await Task.sleep(for: .milliseconds(80))
        return UsageSnapshot(provider: agent.rawValue, status: "ok", account: "test", metrics: [UsageMetric(id: "q", title: "Quota", value: 50, unit: "%", kind: "quota")], collectedAt: Date().timeIntervalSince1970)
    }
}

final class StoreTests: XCTestCase {
    @MainActor func makeStore(_ provider: FakeProvider = FakeProvider()) throws -> UsageStore {
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return UsageStore(container: container, provider: provider)
    }
    @MainActor func testFailureRetainsPreviousSnapshot() throws {
        let store = try makeStore()
        let original = UsageSnapshot(provider: "codex", status: "ok", account: "one", metrics: [UsageMetric(id: "q", title: "Q", value: 0, unit: "%", kind: "quota")], collectedAt: Date().timeIntervalSince1970)
        store.accept(original, for: .codex)
        store.accept(.failure(.codex, code: "auth", message: "Expired"), for: .codex)
        XCTAssertEqual(store.snapshots[.codex]?.metrics?.first?.value, 0)
        XCTAssertTrue(store.stale(.codex))
        XCTAssertEqual(store.history(.codex, days: 7).count, 1)
    }
    @MainActor func testConcurrentRefreshCoalescesAndSleepStopsRefresh() async throws {
        let provider = FakeProvider(); let store = try makeStore(provider)
        store.refresh(.codex); store.refresh(.codex)
        try await Task.sleep(for: .milliseconds(250))
        let count = await provider.count
        XCTAssertEqual(count, 1)
        store.pause(); store.refresh(.codex)
        try await Task.sleep(for: .milliseconds(150))
        let afterSleep = await provider.count
        XCTAssertEqual(afterSleep, 1)
        store.sleeping = false; store.refresh(.codex)
        try await Task.sleep(for: .milliseconds(250))
        let afterWake = await provider.count
        XCTAssertEqual(afterWake, 2)
    }
    @MainActor func testClearHistoryPreventsInFlightRepopulation() async throws {
        let store = try makeStore()
        store.refresh(.codex); store.clearHistory()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertTrue(store.history(.codex, days: 7).isEmpty)
    }
}
