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
    // Optional for snapshots saved before lifetime log collection was introduced.
    var allTimeDays: [LocalUsageDay]? = nil

    enum Period { case week, month, allTime }
    func tokens(in period: Period, now: Date = Date(), timeZone: TimeZone = .current) -> Double? {
        guard let allTimeDays else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday, independent of the system locale.
        let start: Date
        switch period {
        case .week: start = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        case .month: start = calendar.dateInterval(of: .month, for: now)!.start
        case .allTime: start = .distantPast
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return allTimeDays.reduce(0) { total, day in
            guard let date = formatter.date(from: day.date), date >= start, date <= now else { return total }
            return total + day.input + day.output
        }
    }
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
    // Daily observed consumption: drops between consecutive observations inside the same quota
    // window. Resets, top-ups and capture gaps are never counted; days without a drop stay absent.
    static func consumed(_ snapshots: [UsageSnapshot], account: String, metric: String, since: Date, calendar: Calendar = .current, maxGap: TimeInterval = 1800) -> [DailyPoint] {
        let ordered = snapshots.filter { $0.account == account }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        var previous: (date: Date, value: Double, reset: Double?)?
        var totals: [Date: (Date, Double)] = [:]
        for s in ordered {
            guard let date = s.date, let m = s.metrics?.first(where: { $0.id == metric }), m.kind == "quota" else { previous = nil; continue }
            if s.provider == "glm", m.resetAt == nil { previous = nil; continue }
            defer { previous = (date, m.value, m.resetAt) }
            guard let last = previous, date.timeIntervalSince(last.date) <= maxGap else { continue }
            let sameWindow: Bool
            if let a = last.reset, let b = m.resetAt {
                // Antigravity reset times are CLI countdown estimates and drift by minutes;
                // a real window reset shifts them by hours.
                sameWindow = s.provider == "glm" ? a == b : abs(a - b) <= 900
            } else { sameWindow = true }
            guard sameWindow, m.value < last.value else { continue }
            let day = calendar.startOfDay(for: date)
            let drop = last.value - m.value
            totals[day] = (date, (totals[day]?.1 ?? 0) + drop)
        }
        return totals.filter { $0.key >= since }.map { DailyPoint(date: $0.key, actualDate: $0.value.0, value: $0.value.1) }.sorted { $0.date < $1.date }
    }
}
