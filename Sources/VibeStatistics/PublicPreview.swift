import Foundation
import SwiftData

/// Opt-in offline acceptance fixture; never reads user accounts or writes history.
struct PreviewUsageProvider: UsageProvider {
    func fetch(_ source: UsageSource, path: String, node: String, secret: String?) async -> UsageSnapshot {
        UsageSnapshot(provider: source.rawValue, status: "ok", account: secret.map(QueryIdentity.fingerprint) ?? "preview",
            source: "离线演示数据", metrics: [UsageMetric(id: "preview", title: "Coding Plan 剩余额度", value: 72, unit: "%", kind: "quota", used: 28, total: 100, resetAt: Date().addingTimeInterval(7200).timeIntervalSince1970)],
            plan: "离线预览", collectedAt: Date().timeIntervalSince1970)
    }
}

@MainActor enum PublicPreview {
    static var enabled: Bool { CommandLine.arguments.contains("--offline-preview") }
    static func makeStore() throws -> UsageStore {
        let container = try ModelContainer(for: StoredSnapshot.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let defaults = UserDefaults(suiteName: "com.vibestatistics.offline-preview")!
        defaults.setVolatileDomain(["source.codex": "glm", "source.deepseek": "glm"], forName: UserDefaults.argumentDomain)
        let empty = CommandLine.arguments.contains("--preview-empty")
        return UsageStore(container: container, provider: PreviewUsageProvider(), defaults: defaults,
            detector: AgentDetector(environmentPath: "", executable: { !empty && ($0.hasSuffix("/codex") || $0.hasSuffix("/claude")) }),
            credential: { _ in "offline-fixture" }, claudeConfiguration: { nil })
    }
}
