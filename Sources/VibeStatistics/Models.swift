import Foundation
import SwiftData
import SwiftUI

enum Agent: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex, kimi, qoder, deepseek, antigravity
    var id: String { rawValue }
    var name: String {
        switch self { case .codex: "Codex"; case .kimi: "Kimi Code"; case .qoder: "Qoder CN"; case .deepseek: "Claude Code"; case .antigravity: "Antigravity" }
    }
    var subtitle: String {
        switch self { case .codex: "ChatGPT 套餐"; case .kimi: "Kimi 会员额度"; case .qoder: "qodercn · Credits"; case .deepseek: "DeepSeek 官方 API"; case .antigravity: "Google AI · CLI" }
    }
    var symbol: String {
        switch self { case .codex: "terminal"; case .kimi: "moon.stars"; case .qoder: "chevron.left.forwardslash.chevron.right"; case .deepseek: "sparkle"; case .antigravity: "a.circle" }
    }
    var color: Color {
        switch self { case .codex: .primary; case .kimi: .indigo; case .qoder: .teal; case .deepseek: .orange; case .antigravity: .blue }
    }
    var defaultPath: String {
        switch self { case .codex: "~/.local/bin/codex"; case .kimi: "~/.kimi-code/bin/kimi"; case .qoder: "~/.qoder-cn/entry/qodercn"; case .deepseek: "~/.local/bin/claude"; case .antigravity: "~/.local/bin/agy" }
    }
    var portal: URL {
        let address = switch self {
        case .codex: "https://chatgpt.com/codex/settings/usage"
        case .kimi: "https://www.kimi.com/membership/subscription?tab=quota"
        case .qoder: "https://qoder.cn/account/integrations"
        case .deepseek: "https://platform.deepseek.com/usage"
        case .antigravity: "https://one.google.com/ai"
        }
        return URL(string: address)!
    }
    var loginHint: String {
        switch self { case .codex: "在终端运行 codex login"; case .kimi: "在终端运行 kimi login"; case .qoder: "在终端运行 qodercn login，或填入 PAT"; case .deepseek: "复用 ~/.claude/settings.json 中的官方 Key，或在此添加"; case .antigravity: "在终端运行 agy，按官方流程登录" }
    }
}

struct UsageMetric: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: Double
    let unit: String
    let kind: String
    var used: Double?
    var total: Double?
    var resetAt: Double?
    var note: String?
    var fraction: Double? {
        if unit == "%" { return min(1, max(0, value / 100)) }
        if kind == "quota", let total, total > 0 { return min(1, max(0, value / total)) }
        return nil
    }
    var formatted: String {
        let amount = value.formatted(.number.precision(.fractionLength(unit == "Credits" ? 0...2 : 0...2)))
        switch unit { case "%": return "\(amount)%"; case "CNY": return "¥\(value.formatted(.number.precision(.fractionLength(2))))"; case "USD": return "$\(value.formatted(.number.precision(.fractionLength(2))))"; default: return "\(amount) \(unit)" }
    }
}

struct LocalUsageDay: Codable, Identifiable, Sendable {
    var id: String { date }
    let date: String
    let input: Double
    let output: Double
    let cacheRead: Double?
    let cacheWrite: Double?
}
struct LocalUsage: Codable, Sendable {
    let days: [LocalUsageDay]
    let messageCount: Int
    let incomplete: Bool
    let scope: String
}

struct UsageSnapshot: Codable, Sendable {
    let provider: String
    let status: String
    var account: String?
    var source: String?
    var metrics: [UsageMetric]?
    var plan: String?
    var collectedAt: Double?
    var localUsage: LocalUsage?
    var cliVersion: String?
    var notices: [String]?
    var errorCode: String?
    var message: String?
    var date: Date? { collectedAt.map(Date.init(timeIntervalSince1970:)) }
    var isValid: Bool {
        status == "ok" && account?.isEmpty == false && collectedAt != nil && metrics?.isEmpty == false
        && metrics!.allSatisfy { $0.value.isFinite && ($0.unit != "%" || (0...100).contains($0.value)) }
    }
}

@Model final class StoredSnapshot {
    @Attribute(.unique) var identity: String
    var provider: String
    var account: String
    var date: Date
    var payload: Data
    init(_ snapshot: UsageSnapshot) throws {
        provider = snapshot.provider; account = snapshot.account!; date = snapshot.date!
        identity = "\(snapshot.provider)|\(snapshot.account!)|\(snapshot.collectedAt!)"
        payload = try JSONEncoder().encode(snapshot)
    }
    var decoded: UsageSnapshot? { try? JSONDecoder().decode(UsageSnapshot.self, from: payload) }
}

struct DailyPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let actualDate: Date
    let value: Double
}

enum History {
    // Daily closing observation, never a sum or inferred bill. No interpolation over gaps/resets.
    static func daily(_ snapshots: [UsageSnapshot], account: String, metric: String, since: Date, calendar: Calendar = .current) -> [DailyPoint] {
        var last: [Date: (Date, Double)] = [:]
        for s in snapshots where s.account == account {
            guard let date = s.date, date >= since, let m = s.metrics?.first(where: { $0.id == metric }) else { continue }
            let day = calendar.startOfDay(for: date)
            if last[day] == nil || date > last[day]!.0 { last[day] = (date, m.value) }
        }
        return last.map { DailyPoint(date: $0.key, actualDate: $0.value.0, value: $0.value.1) }.sorted { $0.date < $1.date }
    }
}
