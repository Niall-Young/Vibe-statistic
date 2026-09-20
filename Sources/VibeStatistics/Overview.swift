import SwiftUI

// Nico design tokens. Dynamic counterparts keep the existing dark appearance usable.
enum HomeStyle {
    static let surface = color(0xffffff, dark: 0x1c1c1e)
    static let text = Color.primary.opacity(0.86)
    static let subtle = Color.primary.opacity(0.68)
    static let muted = Color.primary.opacity(0.44)
    static let fill = Color.primary.opacity(0.04)
    static let border = Color.primary.opacity(0.08)
    static let positive = color(0x41aa5f, dark: 0x65c981)
    static let information = color(0x0092e0, dark: 0x39b5f7)
    static let negative = color(0xeb0b59, dark: 0xff568e)
    static func quotaColor(_ fraction: Double) -> Color {
        fraction <= 0.25 ? negative : fraction < 0.75 ? information : positive
    }
    private static func color(_ light: UInt, dark: UInt) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct HomeIcon: View {
    let name: String
    var size: CGFloat = 20
    private static let images: [String: NSImage] = {
        let resources = Bundle.main.resourceURL?.appendingPathComponent("VibeStatistics_VibeStatistics.bundle")
        let bundle = resources.flatMap(Bundle.init(url:)) ?? Bundle.module
        return Dictionary(uniqueKeysWithValues: ["overview", "settings", "search", "refresh", "connected"].compactMap { name in
            guard let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "HomeIcons"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return (name, image)
        })
    }()
    var body: some View {
        Group {
            if let image = Self.images[name] {
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct MainView: View {
    @ObservedObject var store: UsageStore
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    private var title: String {
        if store.selection == "settings" { return "设置" }
        return store.selection.flatMap(Agent.init(rawValue:))?.name ?? "总览"
    }
    var body: some View {
        NavigationSplitView {
            List {
                navigationRow("总览", selection: "overview", icon: "overview")
                navigationRow("设置", selection: "settings", icon: "settings")
                HStack {
                    Text("用量详情").font(.system(size: 14)).foregroundStyle(HomeStyle.muted)
                    Spacer()
                    Button {
                        store.selection = "overview"
                        searchFocused = true
                    } label: { HomeIcon(name: "search", size: 16) }
                    .buttonStyle(.plain).help("搜索智能体").accessibilityLabel("搜索智能体")
                }.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 4)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                ForEach(Agent.allCases) { agent in
                    Button { store.selection = agent.rawValue } label: {
                        HStack(spacing: 8) {
                            AgentLogo(agent: agent, size: 24).saturation(0)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeStyle.border))
                            Text(agent.name)
                            Spacer(minLength: 0)
                        }.modifier(SidebarRowStyle(selected: store.selection == agent.rawValue))
                    }.buttonStyle(.plain).accessibilityAddTraits(store.selection == agent.rawValue ? .isSelected : [])
                        .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .padding(.horizontal, 8).padding(.top, 4)
            .background(HomeStyle.surface)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 260)
        } detail: {
            Group {
                if store.selection == "settings" { SettingsView(store: store) }
                else if let selection = store.selection, let agent = Agent(rawValue: selection) {
                    DetailView(store: store, agent: agent).id(agent)
                } else { OverviewView(store: store, search: $search, searchFocused: $searchFocused) }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 10) {
                        Text(title).font(.system(size: 14, weight: .medium))
                        if let date = store.snapshots.values.compactMap(\.date).max() {
                            Text("数据更新于 \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                        }
                    }
                }
                ToolbarItem {
                    Button { store.refresh() } label: { HomeIcon(name: "refresh", size: 16) }
                        .keyboardShortcut("r").help("刷新全部额度 ⌘R")
                        .accessibilityLabel("刷新全部额度").disabled(store.active)
                }
            }
        }
        .navigationTitle("")
        .background(HomeStyle.surface)
        .frame(minWidth: 820, minHeight: 620)
    }
    private func navigationRow(_ title: String, selection: String, icon: String) -> some View {
        Button { store.selection = selection } label: {
            HStack(spacing: 8) {
                HomeIcon(name: icon).frame(width: 24, height: 24)
                Text(title)
                Spacer(minLength: 0)
            }.modifier(SidebarRowStyle(selected: (store.selection ?? "overview") == selection))
        }.buttonStyle(.plain)
            .accessibilityAddTraits((store.selection ?? "overview") == selection ? .isSelected : [])
            .listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
    }
}

private struct SidebarRowStyle: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content.font(.system(size: 14)).foregroundStyle(selected ? HomeStyle.text : HomeStyle.subtle)
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(selected ? HomeStyle.fill : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

struct SegmentedQuotaBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - 38) / 20)
            HStack(spacing: 2) {
                ForEach(0..<20) { index in
                    Rectangle().fill(Color.primary.opacity(0.2))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(HomeStyle.quotaColor(fraction))
                                .frame(width: width * min(1, max(0, fraction * 20 - Double(index))))
                        }.frame(width: width)
                }
            }
        }.frame(height: 20).accessibilityHidden(true)
    }
}

private struct HomeMetricRow: View {
    let metric: UsageMetric
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(metric.title).foregroundStyle(HomeStyle.muted)
                Spacer(minLength: 0)
                Text(metric.formatted).fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(metric.fraction.map(HomeStyle.quotaColor) ?? HomeStyle.text)
            }.font(.system(size: 14)).frame(minHeight: 22)
            if let fraction = metric.fraction { SegmentedQuotaBar(fraction: fraction) }
            if let reset = metric.resetAt {
                Text("\(Date(timeIntervalSince1970: reset).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())) \(metric.note == "套餐到期时间" ? "到期" : "重置")\(metric.note?.contains("估算") == true ? "（估算）" : "")")
                    .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}

private struct HomeStatus: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    private var healthy: Bool { store.snapshots[agent] != nil && store.errors[agent] == nil && !store.stale(agent) }
    var body: some View {
        Group {
            if healthy && !store.refreshing.contains(agent) {
                HStack(spacing: 4) {
                    HomeIcon(name: "connected", size: 16)
                    Text("已连接").font(.system(size: 14))
                }.foregroundStyle(HomeStyle.positive)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(HomeStyle.positive.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else { StatusLabel(store: store, agent: agent) }
        }
    }
}

struct AgentCard: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                AgentLogo(agent: agent, size: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeStyle.border))
                Text(agent.name).font(.system(size: 16, weight: .medium)).fixedSize()
                Spacer(minLength: 0)
                Text(store.snapshots[agent]?.plan ?? agent.subtitle)
                    .font(.system(size: 12)).foregroundStyle(HomeStyle.muted).lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            if let snapshot = store.snapshots[agent], let metrics = snapshot.metrics {
                VStack(spacing: 12) {
                    ForEach(Array(metrics.prefix(2))) { HomeMetricRow(metric: $0) }
                    if metrics.count > 2 {
                        Text("另有 \(metrics.count - 2) 项额度与余额")
                            .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂无数据").font(.system(size: 22, weight: .medium))
                    Text(store.errors[agent]?.message ?? "正在读取本机登录与额度信息…")
                        .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error = store.errors[agent], store.snapshots[agent] != nil {
                Text(error.message ?? "查询失败").font(.caption).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            HStack {
                HomeStatus(store: store, agent: agent)
                Spacer(minLength: 4)
                Button { store.selection = agent.rawValue } label: {
                    Text("用量详情").font(.system(size: 14))
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(HomeStyle.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                }.buttonStyle(.plain).accessibilityLabel("查看 \(agent.name) 用量详情")
            }
        }
        .foregroundStyle(HomeStyle.text)
        .padding(20).frame(maxWidth: .infinity, minHeight: 306, alignment: .topLeading)
        .background(HomeStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HomeStyle.border, lineWidth: 1))
    }
}

struct OverviewView: View {
    @ObservedObject var store: UsageStore
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    private var agents: [Agent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Agent.allCases.filter { query.isEmpty || "\($0.name) \($0.subtitle)".localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width >= 900 ? 4 : 2), spacing: 12) {
                        summary("已连接 Agent", value: "\(store.connected)", unit: "/ 5 个")
                        summary("额度窗口", value: store.snapshots.isEmpty ? "—" : "\(store.snapshots.values.flatMap { $0.metrics ?? [] }.filter { $0.fraction != nil }.count)", unit: "个")
                        summary("本机近 30 天 Token", value: tokenValue, unit: "输入 + 输出")
                        summary("DeepSeek 余额", value: store.snapshots[.deepseek]?.metrics?.first(where: { $0.kind == "balance" })?.formatted ?? "—", unit: store.stale(.deepseek) ? "等待刷新" : "账户余额")
                    }
                    HStack(spacing: 10) {
                        HomeIcon(name: "search", size: 16).foregroundStyle(HomeStyle.muted)
                        TextField("搜索智能体名称", text: $search).textFieldStyle(.plain)
                            .font(.system(size: 14)).focused(searchFocused)
                            .accessibilityLabel("搜索智能体名称")
                        if !search.isEmpty {
                            Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(HomeStyle.muted) }
                                .buttonStyle(.plain).accessibilityLabel("清除搜索")
                        }
                    }.padding(.horizontal, 12).frame(width: 320, height: 32)
                        .background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 8))
                    if let error = store.storageError {
                        Label(error, systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
                    }
                    if agents.isEmpty {
                        ContentUnavailableView.search(text: search).frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(agents) { agent in AgentCard(store: store, agent: agent) }
                        }
                    }
                    Text("额度与金额分别统计；余额变化不等于实际消费。本机 Token 仅含 Claude Code / DeepSeek 日志\(store.snapshots[.deepseek]?.localUsage?.incomplete == true ? "，部分日志无法解析" : "")。")
                        .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }.background(HomeStyle.surface)
        }
    }
    private var tokenValue: String {
        guard let usage = store.snapshots[.deepseek]?.localUsage else { return "—" }
        let total = usage.days.reduce(0) { $0 + $1.input + $1.output }
        return total.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    private func summary(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14)).foregroundStyle(HomeStyle.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).font(.system(size: 12)).foregroundStyle(HomeStyle.subtle).lineLimit(1)
            }.frame(height: 36)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 16)
            .background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 12))
    }
}
