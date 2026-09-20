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
        Picker("外观", selection: $theme) {
            ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
        }
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
        .frame(width: size * (agent == .deepseek ? 0.82 : 0.72), height: size * 0.72)
        // Center Kimi's K optically; the detached blue dot skews its artwork bounds.
        .offset(x: agent == .kimi ? size * 0.07 : 0,
                y: agent == .kimi ? -size * 0.055 : 0)
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.22))
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
        if store.refreshing.contains(agent) {
            HStack(spacing: 5) { ProgressView().controlSize(.mini); Text("刷新中") }.font(.caption).foregroundStyle(.secondary)
        } else if store.errors[agent] != nil {
            Label(store.snapshots[agent] == nil ? "连接待处理" : "数据已过期", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
        } else if store.snapshots[agent] != nil {
            Label(store.stale(agent) ? "等待刷新" : "已连接", systemImage: store.stale(agent) ? "clock" : "checkmark.circle.fill")
                .font(.caption).foregroundStyle(store.stale(agent) ? Color.secondary : .green)
        } else { Text("等待连接").font(.caption).foregroundStyle(.secondary) }
    }
}

struct MetricRow: View {
    let metric: UsageMetric
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title).font(compact ? .caption : .subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(metric.formatted).font(.system(size: compact ? 15 : 22, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            if let fraction = metric.fraction {
                ProgressView(value: fraction).tint(fraction <= 0.05 ? .red : fraction <= 0.2 ? .orange : .accentColor)
                    .accessibilityLabel("\(metric.title) 剩余 \(Int(fraction * 100))%")
            }
            if !compact {
                HStack {
                    if let used = metric.used, let total = metric.total {
                        Text("已用 \(used.formatted(.number.precision(.fractionLength(0...2)))) / \(total.formatted(.number.precision(.fractionLength(0...2))))\(metric.unit == "%" ? "" : " " + metric.unit)")
                    } else { Text(metric.kind == "balance" ? "账户余额" : "剩余额度") }
                    Spacer()
                    if let reset = metric.resetAt {
                        let date = Date(timeIntervalSince1970: reset)
                        Text("\(metric.note == "套餐到期时间" ? "到期" : "重置") \(date.formatted(.dateTime.month().day().hour().minute()))")
                            .help(metric.note ?? "服务返回的时间")
                    }
                }.font(.caption).foregroundStyle(.tertiary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct AgentCard: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AgentIcon(agent: agent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name).font(.headline)
                    Text(agent.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusLabel(store: store, agent: agent)
            }
            if let s = store.snapshots[agent], let metrics = s.metrics {
                VStack(spacing: 12) {
                    ForEach(Array(metrics.prefix(2))) { MetricRow(metric: $0, compact: true) }
                    if metrics.count > 2 { Text("另有 \(metrics.count - 2) 项额度与余额").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                }
                HStack {
                    Text(s.source ?? "官方查询").lineLimit(1)
                    Spacer()
                    if let date = s.date { Text(date, style: .time).monospacedDigit() }
                }.font(.caption2).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("暂无数据").font(.title2.weight(.medium))
                    Text(store.errors[agent]?.message ?? "正在读取本机登录与额度信息…").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            }
            if let e = store.errors[agent], store.snapshots[agent] != nil {
                Text(e.message ?? "查询失败").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.065), lineWidth: 1))
    }
}

struct MainView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section {
                    Label("总览", systemImage: "square.grid.2x2").tag("overview")
                }
                Section("AGENTS") {
                    ForEach(Agent.allCases) { agent in
                        Label { Text(agent.name) } icon: { AgentLogo(agent: agent, size: 20) }.tag(agent.rawValue)
                    }
                }
                Section {
                    Label("设置", systemImage: "gearshape").tag("settings")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 230)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VIBE STATISTICS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    Text("本机采集 · 私有存储").font(.caption2).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        } detail: {
            Group {
                if store.selection == "settings" { SettingsView(store: store) }
                else if let selection = store.selection, let agent = Agent(rawValue: selection) { DetailView(store: store, agent: agent).id(agent) }
                else { OverviewView(store: store) }
            }
            .toolbar {
                ToolbarItem { ThemePicker().frame(width: 150) }
                ToolbarItem {
                    Button { store.refresh() } label: { Label("刷新全部", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r").help("刷新全部额度 ⌘R").disabled(store.active)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 620)
    }
}

struct OverviewView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("用量，一目了然。").font(.system(size: 29, weight: .semibold))
                        Text("五个 Agent 的额度、余额与每日变化。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.connected) / 5 已连接").font(.callout.monospacedDigit()).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.quaternary, in: Capsule())
                }
                if let error = store.storageError { Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(Agent.allCases) { agent in
                        Button { store.selection = agent.rawValue } label: { AgentCard(store: store, agent: agent) }
                            .buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityLabel("查看 \(agent.name) 用量详情，\(store.snapshots[agent]?.metrics?.first?.formatted ?? "暂无数据")").accessibilityAddTraits(.isButton)
                    }
                }
                Label("额度与金额分别统计；余额变化不等于实际消费。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }.background(Color(nsColor: .windowBackgroundColor)).navigationTitle("总览")
    }
}

struct DetailView: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    @State private var days = 7
    @State private var selectedMetric = ""
    var snapshot: UsageSnapshot? { store.snapshots[agent] }
    var metrics: [UsageMetric] { snapshot?.metrics ?? [] }
    var metric: UsageMetric? { metrics.first(where: { $0.id == selectedMetric }) ?? metrics.first }
    var points: [DailyPoint] {
        _ = store.revision
        guard let account = snapshot?.account, let metric else { return [] }
        return History.daily(store.history(agent, days: days), account: account, metric: metric.id, since: Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400)))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    AgentIcon(agent: agent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(agent.name).font(.largeTitle.weight(.semibold))
                        Text(snapshot?.plan ?? agent.subtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusLabel(store: store, agent: agent)
                    Button("刷新") { store.refresh(agent) }.disabled(store.refreshing.contains(agent))
                }
                if let error = store.errors[agent] {
                    Label(error.message ?? "查询失败", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).padding().frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if metrics.isEmpty {
                    ContentUnavailableView("暂无额度数据", systemImage: "chart.bar.xaxis", description: Text(agent.loginHint))
                } else {
                    VStack(spacing: 20) {
                        ForEach(metrics) { item in
                            MetricRow(metric: item)
                            if item.id != metrics.last?.id { Divider() }
                        }
                    }.padding(24).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    if let local = snapshot?.localUsage { LocalUsageView(usage: local) }
                    historySection
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(snapshot?.source ?? "尚未查询成功").font(.caption)
                    if let version = snapshot?.cliVersion { Text("CLI \(version)").font(.caption2) }
                    ForEach(snapshot?.notices ?? [], id: \.self) { Text($0).font(.caption) }
                    if let account = snapshot?.account { Text("账户标识 \(account.prefix(8)) · 不保存账户明文").font(.caption2) }
                    if let date = snapshot?.date { Text("最后更新 \(date.formatted(date: .abbreviated, time: .standard))").font(.caption2) }
                    if agent == .deepseek { Text("余额属于整个 DeepSeek 账户，可能包含其他客户端消耗、充值及赠送额度变化。当前没有足够计费证据，费用估算暂不展示。").font(.caption).fixedSize(horizontal: false, vertical: true) }
                    if metrics.contains(where: { $0.note?.contains("估算") == true }) { Text("Antigravity 重置时间根据 CLI 倒计时估算；百分比为官方面板读数。").font(.caption) }
                    HStack {
                        Link("打开官方账户页面 ↗", destination: agent.portal)
                        Button("接入设置") { store.selection = "settings" }
                    }.padding(.top, 4)
                }.foregroundStyle(.secondary)
            }.padding(28)
        }.navigationTitle(agent.name).background(Color(nsColor: .windowBackgroundColor))
    }
    var historySection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("每日趋势").font(.headline)
                Spacer()
                Picker("时间范围", selection: $days) { Text("7 天").tag(7); Text("30 天").tag(30) }.pickerStyle(.segmented).frame(width: 140)
            }
            if let metric {
                Picker("指标", selection: Binding(get: { selectedMetric.isEmpty ? metric.id : selectedMetric }, set: { selectedMetric = $0 })) {
                    ForEach(metrics) { Text("\($0.title) · \($0.unit)").tag($0.id) }
                }.labelsHidden().frame(maxWidth: 330, alignment: .leading)
                if points.isEmpty {
                    ContentUnavailableView("开始积累趋势", systemImage: "chart.xyaxis.line", description: Text("首次成功刷新后开始记录，不补填过去的数据。")).frame(height: 190)
                } else {
                    Chart(points) { point in
                        PointMark(x: .value("日期", point.date), y: .value(metric.unit, point.value))
                            .foregroundStyle(agent.color).symbolSize(65)
                            .accessibilityLabel(point.actualDate.formatted(date: .abbreviated, time: .shortened))
                            .accessibilityValue("\(point.value) \(metric.unit)")
                    }
                    .chartXScale(domain: Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))...Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400))
                    .chartYScale(domain: metric.unit == "%" ? 0...100 : 0...max((points.map(\.value).max() ?? 1) * 1.15, 1))
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: days == 7 ? 1 : 5)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                    .frame(height: 205)
                    if let last = points.last {
                        Text("最新观测 \(last.value.formatted(.number.precision(.fractionLength(0...2)))) \(metric.unit) · \(last.actualDate.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("每个点为当日最后一次采集值。空缺、额度重置与充值不推算成消费。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("refreshInterval") private var interval = 300.0
    @AppStorage("retentionDays") private var retention = 90
    @AppStorage("nodePath") private var nodePath = "/opt/homebrew/bin/node"
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var message: String?
    @State private var confirmClear = false
    var body: some View {
        Form {
            Section("外观") { ThemePicker().pickerStyle(.segmented) }
            Section("刷新与存储") {
                Picker("自动刷新", selection: $interval) { Text("每 1 分钟").tag(60.0); Text("每 5 分钟").tag(300.0); Text("每 15 分钟").tag(900.0) }
                Picker("保留历史", selection: $retention) { Text("30 天").tag(30); Text("90 天").tag(90) }
                Toggle("登录 Mac 时启动", isOn: $loginEnabled).onChange(of: loginEnabled) { _, value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                    catch { message = "开机启动设置未成功，请检查系统设置中的登录项。"; loginEnabled = SMAppService.mainApp.status == .enabled }
                }
                Text("休眠时停止查询，唤醒后刷新。查询失败保留旧值并逐步延长重试间隔。").font(.caption).foregroundStyle(.secondary)
            }
            Section("CLI 与账户") {
                ForEach(Agent.allCases) { agent in CredentialRow(store: store, agent: agent) }
                TextField("Node.js 路径", text: $nodePath)
                Text("Qoder CN SDK 使用本机 Node.js。Python 辅助程序使用 /usr/bin/python3；不会发送模型任务。").font(.caption).foregroundStyle(.secondary)
            }
            Section("历史数据") {
                Button("清除本机历史记录…", role: .destructive) { confirmClear = true }
                Text("只清除本应用的额度快照，不会修改 CLI 历史或官方账户。").font(.caption).foregroundStyle(.secondary)
            }
            if let message { Section { Text(message).foregroundStyle(.orange) } }
        }
        .formStyle(.grouped).navigationTitle("设置")
        .onChange(of: interval) { store.settingsChanged() }
        .onChange(of: retention) { store.settingsChanged() }
        .confirmationDialog("清除本机历史记录？", isPresented: $confirmClear) {
            Button("清除记录", role: .destructive) { store.clearHistory() }
            Button("取消", role: .cancel) {}
        } message: { Text("此操作不可撤销。下一次刷新将重新开始积累数据。") }
    }
}

struct CredentialRow: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    @State private var path = ""
    @State private var secret = ""
    @State private var saved = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(agent.name).font(.headline); Spacer(); StatusLabel(store: store, agent: agent) }
            if agent != .deepseek {
                TextField("CLI 路径", text: $path).textFieldStyle(.roundedBorder).onSubmit(savePath)
                HStack {
                    Button("保存路径", action: savePath)
                    Button("选择可执行文件…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
                        if panel.runModal() == .OK, let url = panel.url { path = url.path; savePath() }
                    }
                }
            }
            Text(agent.loginHint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if agent == .qoder || agent == .deepseek {
                SecureField(agent == .qoder ? "可选：Qoder CN PAT" : "可选：DeepSeek API Key", text: $secret).textFieldStyle(.roundedBorder)
                HStack {
                    Button("存入钥匙串") {
                        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        do { try Keychain.save(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: agent); secret = ""; saved = true; error = nil; store.reconnect(agent) }
                        catch { self.error = "钥匙串保存失败" }
                    }.disabled(secret.isEmpty)
                    if saved {
                        Text("已保存").font(.caption).foregroundStyle(.green)
                        Button("移除") { do { try Keychain.save("", for: agent); saved = false; store.reconnect(agent) } catch { self.error = "钥匙串移除失败" } }
                    }
                }
            }
            HStack { Link("官方账户页面 ↗", destination: agent.portal); Button("检查连接") { store.refresh(agent) }.disabled(store.refreshing.contains(agent)) }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.vertical, 8).onAppear { path = store.path(agent); saved = Keychain.read(agent) != nil }
    }
    func savePath() { UserDefaults.standard.set(path, forKey: "path.\(agent.rawValue)"); store.reconnect(agent) }
}

struct MenuView: View {
    @ObservedObject var store: UsageStore
    let openWindow: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text("Vibe Statistics").font(.headline); Text("\(store.connected) / 5 已连接").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).disabled(store.active).help("刷新全部")
            }.padding(18)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Agent.allCases) { agent in
                        Button {
                            store.selection = agent.rawValue; openWindow()
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Label { Text(agent.name) } icon: { AgentLogo(agent: agent, size: 20) }.font(.subheadline.weight(.medium)); Spacer(); StatusLabel(store: store, agent: agent) }
                                if let metric = store.snapshots[agent]?.metrics?.first {
                                    MetricRow(metric: metric, compact: true)
                                    if let reset = metric.resetAt {
                                        Text("\(metric.note == "套餐到期时间" ? "到期" : "重置") \(Date(timeIntervalSince1970: reset).formatted(.dateTime.month().day().hour().minute()))").font(.caption2).foregroundStyle(.secondary)
                                    }
                                } else { Text(store.errors[agent]?.message ?? "正在读取额度…").font(.caption).foregroundStyle(.secondary) }
                            }.padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityElement(children: .ignore).accessibilityLabel("\(agent.name)，\(store.snapshots[agent]?.metrics?.first?.formatted ?? "暂无数据")，查看详情").accessibilityAddTraits(.isButton)
                        if agent != Agent.allCases.last { Divider().padding(.horizontal, 18) }
                    }
                }
            }
            Divider()
            HStack {
                Button("打开主窗口", action: openWindow).keyboardShortcut("o")
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }.padding(14)
        }.frame(width: 370, height: 630)
    }
}


struct LocalUsageView: View {
    let usage: LocalUsage
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("本机 Token · 近 30 天").font(.headline); Spacer(); Text("本机日志统计").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 30) {
                tokenTotal("输入", usage.days.reduce(0) { $0 + $1.input })
                tokenTotal("输出", usage.days.reduce(0) { $0 + $1.output })
                tokenTotal("缓存读取", usage.days.allSatisfy { $0.cacheRead != nil } ? usage.days.reduce(0) { $0 + ($1.cacheRead ?? 0) } : nil)
                tokenTotal("缓存写入", usage.days.allSatisfy { $0.cacheWrite != nil } ? usage.days.reduce(0) { $0 + ($1.cacheWrite ?? 0) } : nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Chart(usage.days) { day in
                BarMark(x: .value("日期", day.date), y: .value("输出 Token", day.output)).foregroundStyle(.orange)
            }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }.frame(height: 150)
            Text("每日输出 Token · \(usage.messageCount) 条去重消息。\(usage.scope)。日志可能缺失，不代表官方账单。")
                .font(.caption).foregroundStyle(.secondary)
            if usage.incomplete { Text("部分日志无法解析，统计不完整。").font(.caption).foregroundStyle(.orange) }
        }.padding(24).background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
    func tokenTotal(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value?.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) ?? "暂无数据").font(.title3.weight(.semibold)).monospacedDigit()
        }
    }
}
