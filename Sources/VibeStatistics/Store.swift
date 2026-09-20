import AppKit
import SwiftData
import SwiftUI

@MainActor final class UsageStore: ObservableObject {
    @Published var snapshots: [Agent: UsageSnapshot] = [:]
    @Published var errors: [Agent: UsageSnapshot] = [:]
    @Published var refreshing: Set<Agent> = []
    @Published var selection: String? = "overview"
    @Published var storageError: String?
    @Published var revision = 0
    @Published var sleeping = false
    let container: ModelContainer
    private let provider: any UsageProvider
    private var jobs: [Agent: Task<Void, Never>] = [:]
    private var ticker: Task<Void, Never>?
    private var nextTry: [Agent: Date] = [:]
    private var failures: [Agent: Int] = [:]
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    var interval: TimeInterval { max(60, UserDefaults.standard.double(forKey: "refreshInterval") == 0 ? 300 : UserDefaults.standard.double(forKey: "refreshInterval")) }
    var retention: Int { max(7, UserDefaults.standard.integer(forKey: "retentionDays") == 0 ? 90 : UserDefaults.standard.integer(forKey: "retentionDays")) }
    var connected: Int { Agent.allCases.filter { snapshots[$0] != nil && !stale($0) }.count }
    var active: Bool { !refreshing.isEmpty }
    init(container: ModelContainer, provider: any UsageProvider) {
        self.container = container; self.provider = provider
        for agent in Agent.allCases {
            let key = agent.rawValue
            var descriptor = FetchDescriptor<StoredSnapshot>(predicate: #Predicate { $0.provider == key }, sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 1
            do { snapshots[agent] = try container.mainContext.fetch(descriptor).first?.decoded }
            catch { storageError = "无法读取历史记录" }
        }
        prune()
    }
    func path(_ agent: Agent) -> String { UserDefaults.standard.string(forKey: "path.\(agent.rawValue)") ?? agent.defaultPath }
    func stale(_ agent: Agent) -> Bool {
        guard let date = snapshots[agent]?.date else { return true }
        return errors[agent] != nil || Date().timeIntervalSince(date) > max(600, interval * 2)
    }
    func start() {
        refresh()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { break }
                if !self.sleeping { self.refresh(automatic: true) }
            }
        }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleeping = false; self?.refresh() }
        })
    }
    func pause() {
        sleeping = true; generation += 1
        jobs.values.forEach { $0.cancel() }; jobs.removeAll(); refreshing.removeAll()
        ProcessRegistry.shared.cancelAll()
    }
    func panelOpened() {
        guard !sleeping else { return }
        for agent in Agent.allCases {
            let date = snapshots[agent]?.date ?? .distantPast
            if Date().timeIntervalSince(date) > 60 && (nextTry[agent] ?? .distantPast) <= Date() { refresh(agent) }
        }
    }
    func refresh(_ only: Agent? = nil, automatic: Bool = false) {
        guard !sleeping else { return }
        for agent in only.map({ [$0] }) ?? Agent.allCases {
            guard jobs[agent] == nil else { continue }
            if automatic && (nextTry[agent] ?? .distantPast) > Date() { continue }
            refreshing.insert(agent)
            let ticket = generation
            let path = path(agent)
            let node = UserDefaults.standard.string(forKey: "nodePath") ?? "/opt/homebrew/bin/node"
            let secret: String?
            do { secret = [.deepseek, .qoder].contains(agent) ? try Keychain.read(agent) : nil }
            catch {
                accept(.failure(agent, code: "keychain", message: "凭据需要授权，请在设置中点击「授权读取凭据」；自动刷新不会弹窗"), for: agent)
                refreshing.remove(agent)
                continue
            }
            jobs[agent] = Task { [weak self, provider] in
                let result = await provider.fetch(agent, path: path, node: node, secret: secret)
                guard !Task.isCancelled, let self, self.generation == ticket else { return }
                self.accept(result, for: agent)
                self.jobs.removeValue(forKey: agent); self.refreshing.remove(agent)
            }
        }
    }
    func reconnect(_ agent: Agent) {
        jobs[agent]?.cancel(); jobs.removeValue(forKey: agent); refreshing.remove(agent)
        errors[agent] = .failure(agent, code: "connecting", message: "接入信息已更改，正在重新查询")
        refresh(agent)
    }
    func accept(_ result: UsageSnapshot, for agent: Agent) {
        if result.isValid {
            snapshots[agent] = result; errors.removeValue(forKey: agent); failures[agent] = 0
            nextTry[agent] = Date().addingTimeInterval(interval)
            do {
                container.mainContext.insert(try StoredSnapshot(result)); try container.mainContext.save()
                storageError = nil; revision += 1; prune()
            } catch { container.mainContext.rollback(); storageError = "历史记录保存失败；当前读数仍可查看" }
        } else {
            errors[agent] = result
            failures[agent, default: 0] += 1
            let backoff = min(3600, interval * pow(2, Double(min(failures[agent, default: 1] - 1, 4))))
            nextTry[agent] = Date().addingTimeInterval(backoff)
        }
    }
    func history(_ agent: Agent, days: Int) -> [UsageSnapshot] {
        let key = agent.rawValue
        let since = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))
        let descriptor = FetchDescriptor<StoredSnapshot>(predicate: #Predicate { $0.provider == key && $0.date >= since }, sortBy: [SortDescriptor(\.date)])
        return (try? container.mainContext.fetch(descriptor).compactMap(\.decoded)) ?? []
    }
    func prune() {
        let cutoff = Date().addingTimeInterval(-Double(retention) * 86400)
        do {
            try container.mainContext.delete(model: StoredSnapshot.self, where: #Predicate { $0.date < cutoff })
            try container.mainContext.save()
        } catch { storageError = "历史记录清理失败" }
    }
    func clearHistory() {
        generation += 1; jobs.values.forEach { $0.cancel() }; jobs.removeAll(); refreshing.removeAll()
        ProcessRegistry.shared.cancelAll()
        do {
            try container.mainContext.delete(model: StoredSnapshot.self); try container.mainContext.save()
            snapshots.removeAll(); errors.removeAll(); nextTry.removeAll(); revision += 1; storageError = nil
        } catch { storageError = "历史记录未能删除" }
    }
    func settingsChanged() { nextTry.removeAll(); prune() }
}
