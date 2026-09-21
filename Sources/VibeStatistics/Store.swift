import AppKit
import SwiftData
import SwiftUI

@MainActor final class UsageStore: ObservableObject {
    @Published var snapshots: [Agent: UsageSnapshot] = [:]
    @Published var errors: [Agent: UsageSnapshot] = [:]
    @Published var refreshing: Set<Agent> = []
    @Published private(set) var installedAgents: [Agent] = []
    @Published var selection: String? = "overview"
    @Published var storageError: String?
    @Published var revision = 0
    @Published var sleeping = false
    let container: ModelContainer
    let defaults: UserDefaults
    private let provider: any UsageProvider
    private let detector: AgentDetector
    private let credential: @MainActor (UsageSource) throws -> String?
    private let claudeConfiguration: () -> ClaudeAPIConfiguration?
    private var paths: [Agent: String] = [:]
    private var sources: [Agent: UsageSource] = [:]
    private var identities: [Agent: QueryIdentity] = [:]
    private var jobs: [QueryIdentity: Task<Void, Never>] = [:]
    private var ticker: Task<Void, Never>?
    private var nextTry: [QueryIdentity: Date] = [:]
    private var failures: [QueryIdentity: Int] = [:]
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    var interval: TimeInterval { max(60, defaults.double(forKey: "refreshInterval") == 0 ? 300 : defaults.double(forKey: "refreshInterval")) }
    var retention: Int { max(7, defaults.integer(forKey: "retentionDays") == 0 ? 90 : defaults.integer(forKey: "retentionDays")) }
    var connected: Int { installedAgents.filter { snapshots[$0] != nil && !stale($0) }.count }
    var active: Bool { !refreshing.isEmpty }

    init(container: ModelContainer, provider: any UsageProvider, defaults: UserDefaults = .standard,
         detector: AgentDetector = AgentDetector(),
         credential: @escaping @MainActor (UsageSource) throws -> String? = { try Keychain.read($0) },
         claudeConfiguration: @escaping () -> ClaudeAPIConfiguration? = { ClaudeAPIConfiguration.read() }) {
        self.container = container; self.provider = provider; self.defaults = defaults
        self.detector = detector; self.credential = credential; self.claudeConfiguration = claudeConfiguration
        detectAgents(refreshAfter: false)
        prune()
    }
    func source(_ agent: Agent) -> UsageSource {
        if let raw = defaults.string(forKey: "source.\(agent.rawValue)"), let source = UsageSource(rawValue: raw), agent.sources.contains(source) { return source }
        if agent == .deepseek, let config = claudeConfiguration() { return config.source }
        return agent.nativeSource
    }
    func chooseSource(_ source: UsageSource?, for agent: Agent) {
        if let source, !agent.sources.contains(source) { return }
        defaults.set(source?.rawValue, forKey: "source.\(agent.rawValue)")
        reconfigure()
    }
    func path(_ agent: Agent) -> String { paths[agent] ?? defaults.string(forKey: "path.\(agent.rawValue)") ?? agent.defaultPath }
    func savePath(_ path: String, for agent: Agent) {
        defaults.set(path.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "path.\(agent.rawValue)")
        reconfigure()
    }
    func detectAgents(refreshAfter: Bool = true) {
        var detected: [Agent: String] = [:]
        for agent in Agent.allCases {
            detected[agent] = detector.resolve(agent, custom: defaults.string(forKey: "path.\(agent.rawValue)"))
        }
        let currentSources = Dictionary(uniqueKeysWithValues: detected.keys.map { ($0, source($0)) })
        if detected != paths || currentSources != sources {
            cancelQueries(); paths = detected; sources = currentSources
            installedAgents = Agent.allCases.filter { detected[$0] != nil }
            snapshots = snapshots.filter { detected[$0.key] != nil && $0.value.provider == currentSources[$0.key]?.rawValue }
            errors.removeAll(); identities.removeAll(); nextTry.removeAll()
            if let selected = selection.flatMap(Agent.init(rawValue:)), !installedAgents.contains(selected) { selection = "overview" }
        }
        if refreshAfter { refresh() }
    }
    private func cancelQueries() {
        generation += 1
        jobs.values.forEach { $0.cancel() }; jobs.removeAll(); refreshing.removeAll()
    }
    func reconfigure() {
        cancelQueries(); identities.removeAll(); snapshots.removeAll(); errors.removeAll()
        nextTry.removeAll(); failures.removeAll(); detectAgents(refreshAfter: false); refresh()
    }
    func stale(_ agent: Agent) -> Bool {
        guard let date = snapshots[agent]?.date else { return true }
        return errors[agent] != nil || Date().timeIntervalSince(date) > max(600, interval * 2)
    }
    func sharedAccount(_ agent: Agent) -> Bool {
        guard let identity = identities[agent], identity.source.isAPI else { return false }
        return installedAgents.filter { identities[$0] == identity }.count > 1
    }
    func sourceDescription(_ agent: Agent) -> String {
        source(agent).title + (sharedAccount(agent) ? " · 共享账户额度" : "")
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
            Task { @MainActor in self?.sleeping = false; self?.detectAgents() }
        })
    }
    func pause() { sleeping = true; cancelQueries(); ProcessRegistry.shared.cancelAll() }
    func panelOpened() {
        guard !sleeping else { return }
        detectAgents(refreshAfter: false)
        refresh(automatic: true)
    }
    private func restore(_ agent: Agent, identity: QueryIdentity) {
        let key = identity.source.rawValue
        let account = identity.account
        let api = identity.source.isAPI
        var descriptor = FetchDescriptor<StoredSnapshot>(predicate: #Predicate { $0.provider == key && (!api || $0.account == account) }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        do { snapshots[agent] = try container.mainContext.fetch(descriptor).first?.decoded }
        catch { storageError = "无法读取历史记录" }
    }
    func refresh(_ only: Agent? = nil, automatic: Bool = false) {
        guard !sleeping else { return }
        let requested = installedAgents.filter { only == nil || $0 == only }
        let requestedSources = Set(requested.map { source($0) })
        var secrets: [QueryIdentity: String] = [:]
        // Resolve every installed peer of the requested service before starting work,
        // so the same API key produces one job and one stored snapshot.
        for agent in installedAgents where requestedSources.contains(source(agent)) {
            let service = source(agent)
            do {
                var secret = service.needsSecret ? try credential(service) : nil
                if secret == nil, agent == .deepseek, let config = claudeConfiguration(), config.source == service { secret = config.secret }
                if service.isAPI && (secret?.isEmpty ?? true) {
                    identities.removeValue(forKey: agent); snapshots.removeValue(forKey: agent)
                    errors[agent] = .failure(service, code: "auth", message: "请在设置中配置 \(service.title) 的查询 Key；不会修改 Agent 配置")
                    continue
                }
                let identity = QueryIdentity(source: service, account: service.isAPI ? QueryIdentity.fingerprint(secret!) : path(agent) + (secret.map(QueryIdentity.fingerprint) ?? ""))
                if identities[agent] != identity {
                    identities[agent] = identity; errors.removeValue(forKey: agent); restore(agent, identity: identity)
                }
                if let secret { secrets[identity] = secret }
            } catch {
                identities.removeValue(forKey: agent)
                errors[agent] = .failure(service, code: "keychain", message: "凭据需要授权，请在设置中点击「授权读取凭据」；自动刷新不会弹窗")
            }
        }
        for agent in requested {
            guard let identity = identities[agent], jobs[identity] == nil else { continue }
            if automatic && (nextTry[identity] ?? .distantPast) > Date() { continue }
            let peers = installedAgents.filter { identities[$0] == identity }
            refreshing.formUnion(peers)
            let ticket = generation
            let path = path(agent)
            let override = defaults.string(forKey: "nodePath") ?? ""
            let node = override.isEmpty ? BundledRuntime.node.path : override
            let secret = secrets[identity]
            jobs[identity] = Task { [weak self, provider] in
                let result = await provider.fetch(identity.source, path: path, node: node, secret: secret)
                guard !Task.isCancelled, let self, self.generation == ticket else { return }
                let currentPeers = self.installedAgents.filter { self.identities[$0] == identity }
                guard !currentPeers.isEmpty else { self.jobs.removeValue(forKey: identity); self.refreshing.subtract(peers); return }
                let validIdentity = result.provider == identity.source.rawValue && (!identity.source.isAPI || result.status != "ok" || result.account == identity.account)
                let accepted = validIdentity ? result : .failure(identity.source, code: "format", message: "查询返回的账户或服务不匹配")
                for peer in currentPeers { self.accept(accepted, for: peer, persist: false) }
                if accepted.isValid {
                    self.persist(accepted); self.failures[identity] = 0
                    self.nextTry[identity] = Date().addingTimeInterval(self.interval)
                } else {
                    self.failures[identity, default: 0] += 1
                    self.nextTry[identity] = Date().addingTimeInterval(min(3600, self.interval * pow(2, Double(min(self.failures[identity, default: 1] - 1, 4)))))
                }
                self.jobs.removeValue(forKey: identity); self.refreshing.subtract(currentPeers)
            }
        }
    }
    func reconnect(_ agent: Agent) { reconfigure() }
    func accept(_ result: UsageSnapshot, for agent: Agent, persist shouldPersist: Bool = true) {
        if result.isValid {
            snapshots[agent] = result; errors.removeValue(forKey: agent)
            if shouldPersist { persist(result) }
        } else { errors[agent] = result }
    }
    private func persist(_ result: UsageSnapshot) {
        do {
            container.mainContext.insert(try StoredSnapshot(result)); try container.mainContext.save()
            storageError = nil; revision += 1; prune()
        } catch { container.mainContext.rollback(); storageError = "历史记录保存失败；当前读数仍可查看" }
    }
    func history(_ agent: Agent, days: Int) -> [UsageSnapshot] {
        let key = source(agent).rawValue
        let account = snapshots[agent]?.account ?? ""
        let since = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))
        let descriptor = FetchDescriptor<StoredSnapshot>(predicate: #Predicate { $0.provider == key && $0.account == account && $0.date >= since }, sortBy: [SortDescriptor(\.date)])
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
        cancelQueries(); ProcessRegistry.shared.cancelAll()
        do {
            try container.mainContext.delete(model: StoredSnapshot.self); try container.mainContext.save()
            snapshots.removeAll(); errors.removeAll(); nextTry.removeAll(); revision += 1; storageError = nil
        } catch { storageError = "历史记录未能删除" }
    }
    func settingsChanged() { nextTry.removeAll(); prune() }
}
