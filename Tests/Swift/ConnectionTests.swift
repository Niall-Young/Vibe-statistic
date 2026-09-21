import XCTest
import SwiftData
@testable import VibeStatistics

actor ServiceProvider: UsageProvider {
    var calls: [UsageSource] = []
    func fetch(_ source: UsageSource, path: String, node: String, secret: String?) async -> UsageSnapshot {
        calls.append(source)
        // Deliberately return after cancellation to exercise Store's generation checks.
        try? await Task.sleep(for: .milliseconds(100))
        return UsageSnapshot(provider: source.rawValue, status: "ok",
            account: secret.map(QueryIdentity.fingerprint) ?? "native-account",
            metrics: [UsageMetric(id: "quota", title: "剩余", value: 70, unit: "%", kind: "quota")],
            collectedAt: Date().timeIntervalSince1970)
    }
}

final class ConnectionTests: XCTestCase {
    func testInstallationResolutionAndExplicitBrokenPath() {
        let home = URL(fileURLWithPath: "/test-user")
        let detector = AgentDetector(home: home, environmentPath: "/custom/bin:relative:", executable: {
            ["/custom/bin/codex", "/test-user/.local/bin/claude"].contains($0)
        })
        XCTAssertEqual(detector.resolve(.codex, custom: nil), "/custom/bin/codex")
        XCTAssertEqual(detector.resolve(.deepseek, custom: "~/.local/bin/claude"), "/test-user/.local/bin/claude")
        XCTAssertNil(detector.resolve(.codex, custom: "/missing/codex"))
        XCTAssertNil(detector.resolve(.kimi, custom: nil))
    }
    func testSymlinkAndNonExecutableDetection() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let binary = home.appendingPathComponent("binary")
        try Data("test".utf8).write(to: binary)
        let link = home.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: binary)
        let detector = AgentDetector(home: home, environmentPath: "")
        XCTAssertNil(detector.resolve(.codex, custom: link.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        XCTAssertEqual(detector.resolve(.codex, custom: link.path), binary.resolvingSymlinksInPath().path)
        XCTAssertNil(detector.resolve(.codex, custom: home.path))
    }
    func testClaudeConfigUsesExactOfficialHTTPSHost() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        for (url, expected): (String, UsageSource?) in [
            ("https://open.bigmodel.cn/api/anthropic", .glm), ("https://api.deepseek.com/anthropic", .deepseek),
            ("https://open.bigmodel.cn.evil.test/api/anthropic", nil), ("http://open.bigmodel.cn/api/anthropic", nil),
            ("https://open.bigmodel.cn:8443/api/anthropic", nil), ("https://user@open.bigmodel.cn/api/anthropic", nil)] {
            let data = try JSONSerialization.data(withJSONObject: ["env": ["ANTHROPIC_BASE_URL": url, "ANTHROPIC_AUTH_TOKEN": "fake-key"]])
            try data.write(to: directory.appendingPathComponent("settings.json"))
            XCTAssertEqual(ClaudeAPIConfiguration.read(home: home)?.source, expected)
        }
    }
    @MainActor func testNoInstalledAgentsNeverReadCredentialsOrQuery() async throws {
        let provider = ServiceProvider()
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = UsageStore(container: container, provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            detector: AgentDetector(executable: { _ in false }), credential: { _ in XCTFail("Unexpected credential read"); return nil }, claudeConfiguration: { nil })
        store.refresh(); store.refresh(.deepseek); store.panelOpened()
        try await Task.sleep(for: .milliseconds(160))
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty); XCTAssertTrue(store.installedAgents.isEmpty)
    }
    @MainActor func testSharedKeyCoalescesAndChangingSourceRejectsOldResult() async throws {
        let provider = ServiceProvider()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("glm", forKey: "source.codex"); defaults.set("glm", forKey: "source.kimi")
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = UsageStore(container: container, provider: provider, defaults: defaults,
            detector: AgentDetector(executable: { $0.hasSuffix("/codex") || $0.hasSuffix("/kimi") }),
            credential: { _ in "same-fake-key" }, claudeConfiguration: { nil })
        store.refresh(); store.refresh()
        try await Task.sleep(for: .milliseconds(180))
        let calls = await provider.calls
        XCTAssertEqual(calls, [.glm]); XCTAssertTrue(store.sharedAccount(.codex))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StoredSnapshot>()), 1)
        store.refresh()
        store.chooseSource(.deepseek, for: .codex)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(store.snapshots[.codex]?.provider, "deepseek")
        XCTAssertEqual(store.snapshots[.kimi]?.provider, "glm")
        XCTAssertFalse(store.sharedAccount(.codex))
        XCTAssertTrue(store.history(.codex, days: 7).allSatisfy { $0.provider == "deepseek" })
    }
    @MainActor func testUninstallRemovesSelectionWithoutDeletingHistory() async throws {
        var installed = true
        let provider = ServiceProvider()
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = UsageStore(container: container, provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            detector: AgentDetector(executable: { installed && $0.hasSuffix("/codex") }), credential: { _ in nil }, claudeConfiguration: { nil })
        store.refresh(); try await Task.sleep(for: .milliseconds(160))
        store.selection = "codex"; installed = false; store.detectAgents()
        XCTAssertEqual(store.selection, "overview"); XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<StoredSnapshot>()), 1)
    }
    @MainActor func testKeyRotationDoesNotRestoreDifferentAccountsHistory() async throws {
        var secret = "first-key"
        let provider = ServiceProvider()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("glm", forKey: "source.codex")
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = UsageStore(container: container, provider: provider, defaults: defaults,
            detector: AgentDetector(executable: { $0.hasSuffix("/codex") }), credential: { _ in secret }, claudeConfiguration: { nil })
        store.refresh(); try await Task.sleep(for: .milliseconds(160))
        secret = "second-key"; store.reconfigure()
        XCTAssertNil(store.snapshots[.codex])
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(store.snapshots[.codex]?.account, QueryIdentity.fingerprint(secret))
        XCTAssertEqual(store.history(.codex, days: 7).count, 1)
    }
    @MainActor func testDeniedKeychainDoesNotFallBackToClaudeConfig() async throws {
        let provider = ServiceProvider()
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = UsageStore(container: container, provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            detector: AgentDetector(executable: { $0.hasSuffix("/claude") }),
            credential: { _ in throw NSError(domain: "test-keychain", code: 1) },
            claudeConfiguration: { ClaudeAPIConfiguration(source: .glm, secret: "must-not-be-used") })
        store.refresh(); try await Task.sleep(for: .milliseconds(150))
        let calls = await provider.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(store.errors[.deepseek]?.errorCode, "keychain")
        XCTAssertTrue(store.installedAgents.contains(.deepseek))
    }
    @MainActor func testLegacyDeepSeekSnapshotRestoresWithOriginalIdentity() throws {
        let provider = ServiceProvider()
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let original = UsageSnapshot(provider: "deepseek", status: "ok", account: QueryIdentity.fingerprint("legacy-key"),
            metrics: [UsageMetric(id: "CNY.balance", title: "Balance", value: 42, unit: "CNY", kind: "balance")], collectedAt: Date().timeIntervalSince1970)
        container.mainContext.insert(try StoredSnapshot(original)); try container.mainContext.save()
        let store = UsageStore(container: container, provider: provider, defaults: UserDefaults(suiteName: UUID().uuidString)!,
            detector: AgentDetector(executable: { $0.hasSuffix("/claude") }), credential: { _ in "legacy-key" }, claudeConfiguration: { nil })
        store.refresh()
        XCTAssertEqual(store.snapshots[.deepseek]?.metrics?.first?.value, 42)
        XCTAssertEqual(store.history(.deepseek, days: 7).count, 1)
        store.pause()
    }

}
