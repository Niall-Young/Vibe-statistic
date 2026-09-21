import SwiftUI
import Charts
import ServiceManagement

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" } }
    @MainActor func apply() {
        NSApp.appearance = switch self { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}

struct ThemePicker: View {
    @AppStorage("appTheme") private var theme = AppTheme.system
    var body: some View {
        NicoSegmentedPicker(title: "外观", selection: $theme,
            options: AppTheme.allCases.map { NicoOption(value: $0, title: $0.title) })
            .frame(width: 300)
        .onChange(of: theme) { _, value in value.apply() }
        .help("切换浅色、深色或跟随系统")
    }
}

struct AgentLogo: View {
    let agent: Agent
    var size: CGFloat = 24
    private static let images: [Agent: NSImage] = Dictionary(uniqueKeysWithValues: Agent.allCases.compactMap { agent in
        let name = agent == .deepseek ? "claudecode" : agent.rawValue
        let resources = Bundle.main.resourceURL?.appendingPathComponent("VibeStatistics_VibeStatistics.bundle")
        let bundle = resources.flatMap { Bundle(url: $0) } ?? Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "AgentLogos"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (agent, image)
    })
    var body: some View {
        Group {
            if let image = Self.images[agent] {
                Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AgentIcon: View {
    let agent: Agent
    var body: some View {
        AgentLogo(agent: agent, size: 40)
    }
}

struct StatusLabel: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    var body: some View {
        Group {
            if !store.installedAgents.contains(agent) {
                NicoTag(color: "grey", size: .sm) { Text("未检测到安装") }
            } else if store.refreshing.contains(agent) {
                NicoTag(color: "grey", size: .sm) {
                    HStack(spacing: 4) { ProgressView().controlSize(.mini); Text("刷新中") }
                }
            } else if store.snapshots[agent] != nil && store.stale(agent) {
                StaleStatusTag()
            } else if store.errors[agent] != nil {
                NicoTag(color: "orange", size: .sm) {
                    Label { Text("连接待处理") } icon: { MingCuteIcon(.alert, size: 14) }
                }
            } else if store.snapshots[agent] != nil {
                NicoTag(color: "green", size: .sm) {
                    Label { Text("已连接") } icon: { MingCuteIcon(.connected, size: 14) }
                }
            } else {
                NicoTag(color: "grey", size: .sm) { Text("等待连接") }
            }
        }.fixedSize()
    }
}

struct MetricRow: View {
    let metric: UsageMetric
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title).nicoTypography(compact ? "12/Regular/Default" : "14/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
                Spacer(minLength: 8)
                Text(metric.formatted).nicoTypography(compact ? "16/Bold/Default" : "24/Bold/Default").monospacedDigit()
            }
            if let fraction = metric.fraction {
                SegmentedQuotaBar(fraction: fraction, height: compact ? 8 : 20)
                    .accessibilityHidden(false)
                    .accessibilityLabel("\(metric.title) 剩余 \(Int(fraction * 100))%")
            }
            if !compact {
                HStack {
                    if let used = metric.used, let total = metric.total {
                        Text("已用 \(used.formatted(.number.precision(.fractionLength(0...2)))) / \(total.formatted(.number.precision(.fractionLength(0...2))))\(metric.unit == "%" ? "" : " " + metric.unit)")
                    } else { Text(metric.kind == "balance" ? "账户余额" : "剩余额度") }
                    Spacer()
                }.nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtlest))
            }
            if let reset = metric.resetAt {
                let date = Date(timeIntervalSince1970: reset)
                Text("\(metric.note == "套餐到期时间" ? "到期" : "重置") \(date.formatted(.dateTime.month().day().hour().minute()))\(metric.note?.contains("估算") == true ? "（估算）" : "")")
                    .nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
                    .fixedSize(horizontal: false, vertical: true)
                    .help(metric.note ?? "服务返回的时间，按本机时区显示")
            }
        }.accessibilityElement(children: .combine)
    }
}

struct DetailView: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    @State private var days = 7
    @State private var selectedMetric = ""
    var snapshot: UsageSnapshot? { store.snapshots[agent] }
    var metrics: [UsageMetric] { snapshot?.metrics ?? [] }
    // Consumption only applies to quota windows and credit buckets; balances are excluded
    // because a balance change is not necessarily consumption.
    var visibleMetrics: [UsageMetric] { metrics.filter { $0.kind == "quota" } }
    var metric: UsageMetric? { visibleMetrics.first(where: { $0.id == selectedMetric }) ?? visibleMetrics.first }
    var sinceDate: Date { Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400)) }
    var consumedPoints: [DailyPoint] {
        _ = store.revision
        guard let account = snapshot?.account, let metric else { return [] }
        // One extra day of snapshots gives the first displayed day its opening observation pair.
        return History.consumed(store.history(agent, days: days + 1), account: account, metric: metric.id, since: sinceDate, maxGap: max(600, store.interval * 2))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AgentIcon(agent: agent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(agent.name).nicoTypography("28/Bold/Default")
                        Text(store.sourceDescription(agent)).foregroundStyle(Nico.color(.colorTextSubtle))
                        if let plan = snapshot?.plan { Text(plan).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    StatusLabel(store: store, agent: agent)
                    Button("刷新") { store.refresh(agent) }.disabled(store.refreshing.contains(agent))
                }
                if metrics.isEmpty {
                    ContentUnavailableView { Label { Text("暂无额度数据") } icon: { MingCuteIcon(.chart, size: 48) } } description: { Text(agent.loginHint) }
                } else {
                    VStack(spacing: 20) {
                        ForEach(metrics) { item in
                            MetricRow(metric: item)
                            if item.id != metrics.last?.id { Divider() }
                        }
                    }.padding(24).nicoCard()
                    if agent == .deepseek, let local = snapshot?.localUsage { LocalUsageView(usage: local) }
                    historySection
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot?.source ?? "尚未查询成功").nicoTypography("12/Regular/Default")
                    if let version = snapshot?.cliVersion { Text("CLI \(version)").nicoTypography("12/Regular/Default") }
                    ForEach(snapshot?.notices ?? [], id: \.self) { Text($0).nicoTypography("12/Regular/Default") }
                    if let account = snapshot?.account { Text("账户标识 \(account.prefix(8)) · 不保存账户明文").nicoTypography("12/Regular/Default") }
                    if let date = snapshot?.date { Text("最后更新 \(date.formatted(date: .abbreviated, time: .standard))").nicoTypography("12/Regular/Default") }
                    if agent == .deepseek { Text("余额属于整个 DeepSeek 账户，可能包含其他客户端消耗、充值及赠送额度变化。当前没有足够计费证据，费用估算暂不展示。").nicoTypography("12/Regular/Default").fixedSize(horizontal: false, vertical: true) }
                    if metrics.contains(where: { $0.note?.contains("估算") == true }) { Text("Antigravity 重置时间根据 CLI 倒计时估算；百分比为官方面板读数。").nicoTypography("12/Regular/Default") }
                    HStack {
                        Link(destination: store.source(agent).portal) { HStack(spacing: 4) { Text("打开官方账户页面"); MingCuteIcon(.externalLink, size: 14) } }
                        Button("接入设置") { store.selection = "settings" }
                    }.padding(.top, 4)
                }.foregroundStyle(Nico.color(.colorTextSubtle))
            }.padding(28)
        }.navigationTitle(agent.name).background(Nico.color(.colorSurface))
            .buttonStyle(NicoButtonStyle(kind: "ghost"))
            .tint(Nico.color(.colorBackgroundBrandIntense))
    }
    var historySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("每日趋势").nicoTypography("16/Medium/Default")
                Spacer()
                NicoSegmentedPicker(title: "时间范围", selection: $days, options: [NicoOption(value: 7, title: "7 天"), NicoOption(value: 30, title: "30 天")]).frame(width: 160)
            }
            if let metric {
                let unitLabel = metric.unit == "%" ? "百分点" : metric.unit
                NicoSelect(title: "指标", selection: Binding(get: { metric.id }, set: { selectedMetric = $0 }),
                    options: visibleMetrics.map { NicoOption(value: $0.id, title: "\($0.title) · \($0.unit)") })
                    .frame(width: 320)
                if consumedPoints.isEmpty {
                    ContentUnavailableView { Label { Text("开始积累消耗") } icon: { MingCuteIcon(.trend, size: 48) } } description: { Text("首次成功刷新后开始记录，不补填过去的数据。") }.frame(height: 190)
                } else {
                    Chart(consumedPoints) { point in
                        BarMark(x: .value("日期", point.date, unit: .day), y: .value(unitLabel, point.value), width: .ratio(0.55))
                            .foregroundStyle(Nico.color(.colorBackgroundBrandIntense)).cornerRadius(4)
                            .accessibilityLabel(point.actualDate.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityValue("\(point.value) \(unitLabel)")
                    }
                    .chartXScale(domain: Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))...Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400))
                    .chartYScale(domain: 0...max((consumedPoints.map(\.value).max() ?? 1) * 1.15, 1))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                    .frame(height: 205)
                }
            }
        }.padding(24).nicoCard()
    }
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var updater = AppUpdater.shared
    @AppStorage("refreshInterval") private var interval = 300.0
    @AppStorage("retentionDays") private var retention = 90
    @AppStorage("nodePath") private var nodePath = ""
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var confirmClear = false
    var body: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            NicoSettingsSection(title: "外观") { ThemePicker() }
            NicoSettingsSection(title: "刷新与存储") {
                HStack {
                    Text("自动刷新")
                    Spacer()
                    NicoSelect(title: "自动刷新", selection: $interval, options: [NicoOption(value: 60.0, title: "每 1 分钟"), NicoOption(value: 300.0, title: "每 5 分钟"), NicoOption(value: 900.0, title: "每 15 分钟")]).frame(width: 200)
                }
                HStack {
                    Text("保留历史")
                    Spacer()
                    NicoSelect(title: "保留历史", selection: $retention, options: [NicoOption(value: 30, title: "30 天"), NicoOption(value: 90, title: "90 天")]).frame(width: 200)
                }
                Toggle("登录 Mac 时启动", isOn: $loginEnabled).toggleStyle(NicoSwitchStyle()).onChange(of: loginEnabled) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                Text("休眠时停止查询，唤醒后刷新。查询失败保留旧值并逐步延长重试间隔。").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
            }
            NicoSettingsSection(title: "CLI 与账户") {
                Button("重新检测") { store.detectAgents() }
                ForEach(Agent.allCases) { agent in
                    CredentialRow(store: store, agent: agent)
                    if agent != Agent.allCases.last { Divider() }
                }
                Divider()
                NicoTextField(title: "Node.js 路径", text: $nodePath)
                Text("留空使用应用内置 Node.js；Python 已内置。只查询额度，不发送模型任务。").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
            }
            NicoSettingsSection(title: "历史数据") {
                Button("清除本机历史记录…", role: .destructive) { confirmClear = true }
                Text("只清除本应用的额度快照，不会修改 CLI 历史或官方账户。").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
            }
            NicoSettingsSection(title: "关于与更新") {
                HStack(spacing: 12) {
                    Text("当前版本 \(updater.currentVersion ?? "开发构建")")
                    Spacer()
                    updateStatusView
                }
                if case .available(let release) = updater.phase, !release.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(String(release.notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)))
                        .nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
                        .textSelection(.enabled)
                }
                if case .error(let message) = updater.phase {
                    Text(message).nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextNegative))
                }
                Text("更新包来自官方 GitHub Release，安装前会校验 SHA-256；替换完成后应用自动重启。").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
            }
          }.padding(28).frame(maxWidth: 1000)
              .frame(maxWidth: .infinity)
        }
        .nicoTypography("14/Regular/Default")
        .background(Nico.color(.colorSurface)).navigationTitle("设置")
        .buttonStyle(NicoButtonStyle(kind: "ghost"))
        .tint(Nico.color(.colorBackgroundBrandIntense))
        .onChange(of: interval) { store.settingsChanged() }
        .onChange(of: retention) { store.settingsChanged() }
        .onChange(of: nodePath) { store.reconfigure() }
        .confirmationDialog("清除本机历史记录？", isPresented: $confirmClear) {
            Button("清除记录", role: .destructive) { store.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: { Text("此操作不可撤销。下一次刷新将重新开始积累数据。") }
        .onAppear { updater.checkForUpdates(userInitiated: false) }
    }
    @ViewBuilder private var updateStatusView: some View {
        switch updater.phase {
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在检查…").foregroundStyle(Nico.color(.colorTextSubtle)) }
        case .downloading(let fraction):
            HStack(spacing: 8) { ProgressView(value: fraction).frame(width: 120); Text("正在下载 \(Int(fraction * 100))%").foregroundStyle(Nico.color(.colorTextSubtle)) }
        case .installing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在安装…").foregroundStyle(Nico.color(.colorTextSubtle)) }
        case .available(let release):
            Button("更新到 \(release.version)") { updater.downloadAndInstall(release) }
        case .upToDate:
            HStack(spacing: 12) {
                Text("已是最新版本").foregroundStyle(Nico.color(.colorTextSubtle))
                Button("重新检查") { updater.checkForUpdates(userInitiated: true) }
            }
        case .idle, .error:
            Button("检查更新") { updater.checkForUpdates(userInitiated: true) }
        }
    }
}

struct CredentialRow: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    @State private var path = ""
    @State private var secret = ""
    @State private var saved = false
    @State private var editingPath = false
    @State private var editingSecret = false
    @State private var credentialMessage: String?
    private var service: UsageSource { store.source(agent) }
    private var sourceSelection: Binding<String> {
        Binding(get: { store.defaults.string(forKey: "source.\(agent.rawValue)") ?? "auto" }, set: { value in
            store.chooseSource(UsageSource(rawValue: value), for: agent)
            secret = ""; saved = false; editingSecret = false; credentialMessage = nil
        })
    }
    private let labelWidth: CGFloat = 64
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(agent.name).nicoTypography("16/Medium/Default"); Spacer(); StatusLabel(store: store, agent: agent) }
            Text(service.isAPI ? "查询账户额度；可填写查询 Key，或读取 Claude Code 的匹配配置。" : agent.loginHint).nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle)).textSelection(.enabled)
            pathRow
            if agent != .antigravity {
                NicoSelect(title: "用量来源", selection: sourceSelection,
                    options: [NicoOption(value: "auto", title: "自动识别 / 默认接入")] + agent.sources.map { NicoOption(value: $0.rawValue, title: $0.title) })
            }
            if service.needsSecret { secretRow }
            if let credentialMessage { Text(credentialMessage).font(.caption).foregroundStyle(.orange) }
            HStack {
                Link(destination: service.portal) { HStack(spacing: 4) { Text("官方账户页面"); MingCuteIcon(.externalLink, size: 14) } }
                Spacer()
                Button("检查连接") { store.refresh(agent) }.disabled(!store.installedAgents.contains(agent) || store.refreshing.contains(agent))
            }.padding(.top, 2)
        }.onAppear { path = store.path(agent); saved = Keychain.reader.cache[service] != nil }
    }
    var pathRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("CLI 路径").foregroundStyle(Nico.color(.colorTextSubtle)).frame(width: labelWidth, alignment: .leading)
                if editingPath {
                    NicoTextField(title: "CLI 路径", text: $path).onSubmit(savePath)
                } else {
                    Text(path).font(.system(size: 13, design: .monospaced)).foregroundStyle(Nico.color(.colorTextSubtle))
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    Spacer()
                    Button("更改") { editingPath = true }
                }
            }
            if editingPath {
                HStack(spacing: 8) {
                    Button("选择可执行文件…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url { path = url.path; savePath() }
                    }
                    Spacer()
                    Button("取消") { path = store.path(agent); editingPath = false }
                    Button("保存", action: savePath)
                }
            }
        }
    }
    var secretRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(service == .qoder ? "PAT" : "API Key").foregroundStyle(Nico.color(.colorTextSubtle)).frame(width: labelWidth, alignment: .leading)
                if editingSecret {
                    NicoTextField(title: service.title + " 查询凭据", text: $secret, secure: true)
                } else {
                    Text(saved ? "已存入钥匙串" : "使用已有配置或添加查询 Key").foregroundStyle(Nico.color(.colorTextSubtle))
                    Spacer()
                }
            }
            if service.isAPI { Text("此服务的查询 Key 在已关联 Agent 间共享。").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                Spacer()
                if editingSecret {
                    Button("取消") { secret = ""; editingSecret = false }
                    Button("存入钥匙串") {
                        let value = secret.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        do { try Keychain.save(value, for: service) } catch { credentialMessage = "保存凭据失败"; return }
                        secret = ""; saved = true; editingSecret = false; store.reconnect(agent)
                    }.disabled(secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("授权读取凭据") {
                        do { saved = try Keychain.read(service, allowInteraction: true) != nil; credentialMessage = saved ? "凭据已授权" : "钥匙串中没有此服务的凭据"; store.reconfigure() }
                        catch { credentialMessage = "无法读取凭据，请重试或重新保存" }
                    }.disabled(!store.installedAgents.contains(agent))
                    Button("移除", role: .destructive) {
                        do { try Keychain.save("", for: service); saved = false; credentialMessage = "已移除保存的 Key；仍可使用匹配的本地配置"; store.reconfigure() }
                        catch { credentialMessage = "移除凭据失败" }
                    }
                    Button(saved ? "更新…" : "添加…") { editingSecret = true }
                }
            }
        }
    }
    func savePath() { store.savePath(path, for: agent); editingPath = false }
}

struct MenuView: View {
    @ObservedObject var store: UsageStore
    let openWindow: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vibe Statistics").nicoTypography("16/Medium/Default")
                Spacer()
                Button { store.refresh() } label: { MingCuteIcon(.refresh, size: 16) }.buttonStyle(NicoIconButtonStyle(size: .sm, kind: "plain")).disabled(store.active).help("刷新全部").accessibilityLabel("刷新全部")
            }.padding(.horizontal, 18).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    if store.installedAgents.isEmpty { Text("未检测到支持的 Agent，请打开设置检查安装路径。").padding() }
                    ForEach(store.installedAgents) { agent in
                        Button {
                            store.selection = agent.rawValue; openWindow()
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Label { Text(agent.name) } icon: { AgentLogo(agent: agent, size: 20) }.font(.subheadline.weight(.medium)); Spacer(); StatusLabel(store: store, agent: agent) }
                                Text(store.sourceDescription(agent)).font(.caption).foregroundStyle(.secondary)
                                if let metrics = store.snapshots[agent]?.metrics, !metrics.isEmpty {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach(metrics) { metric in
                                            MetricRow(metric: metric, compact: true)
                                        }
                                    }
                                } else { Text(store.errors[agent]?.message ?? "等待查询额度").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle)) }
                            }.padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityHint("查看 \(agent.name) 详情")
                        if agent != store.installedAgents.last { Divider().padding(.horizontal, 18) }
                    }
                }
            }
            Divider()
            HStack {
                Button("打开主窗口", action: openWindow).keyboardShortcut("o")
                Spacer()
                Button { NSApp.terminate(nil) } label: { MingCuteIcon(.power, size: 16) }
                    .buttonStyle(NicoIconButtonStyle(size: .sm, kind: "plain"))
                    .keyboardShortcut("q")
                    .help("退出 Vibe Statistics")
                    .accessibilityLabel("退出 Vibe Statistics")
            }.padding(14)
        }.frame(width: 370, height: 630)
            .foregroundStyle(Nico.color(.colorText))
            .background(Nico.color(.colorSurface))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .buttonStyle(NicoButtonStyle(size: .sm, kind: "ghost"))
            .tint(Nico.color(.colorBackgroundBrandIntense))
    }
}


struct LocalUsageView: View {
    let usage: LocalUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("本机 Token · 近 30 天").nicoTypography("16/Medium/Default"); Spacer(); Text("本机日志统计").nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                tokenTotal("输入", usage.days.reduce(0) { $0 + $1.input })
                tokenTotal("输出", usage.days.reduce(0) { $0 + $1.output })
                tokenTotal("缓存读取", usage.days.allSatisfy { $0.cacheRead != nil } ? usage.days.reduce(0) { $0 + ($1.cacheRead ?? 0) } : nil)
                tokenTotal("缓存写入", usage.days.allSatisfy { $0.cacheWrite != nil } ? usage.days.reduce(0) { $0 + ($1.cacheWrite ?? 0) } : nil)
            }
            Chart(usage.days) { day in
                BarMark(x: .value("日期", day.date), y: .value("输出 Token", day.output)).foregroundStyle(Nico.color(.colorTextAccentOrange))
            }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }.frame(height: 150)
            Text("每日输出 Token · \(usage.messageCount) 条去重消息。\(usage.scope)。日志可能缺失，不代表官方账单。")
                .nicoTypography("12/Regular/Default").foregroundStyle(Nico.color(.colorTextSubtle))
        }.padding(24).nicoCard()
    }
    func tokenTotal(_ title: String, _ value: Double?) -> some View {
        let parts = value.map(compactParts)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).nicoTypography("14/Regular/Default").foregroundStyle(HomeStyle.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(parts?.0 ?? "暂无数据").nicoTypography("28/Bold/Default").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                if let unit = parts?.1 { Text(unit).nicoTypography("16/Regular/Default").foregroundStyle(HomeStyle.subtle).lineLimit(1) }
            }.frame(height: 36)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 16)
            .background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 12))
    }
    private func compactParts(_ value: Double) -> (String, String) {
        let zh = Locale(identifier: "zh_CN")
        if value >= 100_000_000 { return ((value / 100_000_000).formatted(.number.locale(zh).precision(.fractionLength(0...1))), "亿 token") }
        if value >= 10_000 { return ((value / 10_000).formatted(.number.locale(zh).precision(.fractionLength(0...1))), "万 token") }
        return (value.formatted(.number.locale(zh).precision(.fractionLength(0))), "token")
    }
}
