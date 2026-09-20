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

// The shell is intentionally custom: NavigationSplitView/List/Toolbar add
// macOS 26 floating glass and system insets that are absent from the design.
struct MainView: View {
    @ObservedObject var store: UsageStore
    @State private var search = ""
    @State private var sidebarVisible = true
    @FocusState private var searchFocused: Bool
    private var title: String {
        if store.selection == "settings" { return "设置" }
        return store.selection.flatMap(Agent.init(rawValue:))?.name ?? "总览"
    }
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                VStack(spacing: 0) {
                    windowHeader
                    ScrollView {
                        VStack(spacing: 0) {
                            navigationRow("总览", selection: "overview", icon: .overview)
                            navigationRow("设置", selection: "settings", icon: .settings)
                            HStack {
                                Text("用量详情").font(.system(size: 14)).foregroundStyle(HomeStyle.muted)
                                Spacer()
                                Button {
                                    store.selection = "overview"
                                    searchFocused = true
                                } label: { MingCuteIcon(.search, size: 16) }
                                .buttonStyle(.plain).help("搜索智能体").accessibilityLabel("搜索智能体")
                            }.padding(.leading, 12).padding(.trailing, 5)
                                .frame(height: 22).padding(.top, 16).padding(.bottom, 4)
                            ForEach(Agent.allCases) { agent in
                                Button { store.selection = agent.rawValue } label: {
                                    HStack(spacing: 8) {
                                        AgentLogo(agent: agent, size: 24)
                                            .saturation(store.selection == agent.rawValue ? 1 : 0)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeStyle.border))
                                        Text(agent.name)
                                        Spacer(minLength: 0)
                                    }.modifier(SidebarRowStyle(selected: store.selection == agent.rawValue))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(store.selection == agent.rawValue ? .isSelected : [])
                            }
                        }.padding(.horizontal, 8)
                    }
                }.frame(width: 239).frame(maxHeight: .infinity)
                    .background(HomeStyle.surface)
                Rectangle().fill(HomeStyle.border).frame(width: 1)
            }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if !sidebarVisible { windowHeader.fixedSize() }
                    Text(title).font(.system(size: 14, weight: .medium))
                    if let date = store.snapshots.values.compactMap(\.date).max() {
                        Text("数据更新于 \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 12)).foregroundStyle(HomeStyle.muted)
                    }
                    Spacer()
                    Button { store.refresh() } label: {
                        MingCuteIcon(.refresh, size: 16).frame(width: 32, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).keyboardShortcut("r").help("刷新全部额度 ⌘R")
                        .accessibilityLabel("刷新全部额度").disabled(store.active)
                }.padding(.horizontal, 20).frame(height: 52)
                    .background(WindowDragArea())
                Group {
                    if store.selection == "settings" { SettingsView(store: store) }
                    else if let selection = store.selection, let agent = Agent(rawValue: selection) {
                        DetailView(store: store, agent: agent).id(agent)
                    } else { OverviewView(store: store, search: $search, searchFocused: $searchFocused) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(HomeStyle.text).background(HomeStyle.surface)
        .frame(minWidth: 820, minHeight: 620).ignoresSafeArea()
    }
    private var windowHeader: some View {
        HStack(spacing: 20) {
            WindowControls()
            Button { sidebarVisible.toggle() } label: {
                MingCuteIcon(.sidebar, size: 16).frame(width: 32, height: 32).contentShape(Rectangle())
            }.buttonStyle(.plain).help(sidebarVisible ? "隐藏边栏" : "显示边栏")
                .accessibilityLabel(sidebarVisible ? "隐藏边栏" : "显示边栏")
            Spacer(minLength: 0)
        }.padding(.leading, 20).padding(.trailing, 13).frame(height: 52)
            .background(WindowDragArea())
    }
    private func navigationRow(_ title: String, selection: String, icon: MingCuteSymbol) -> some View {
        Button { store.selection = selection } label: {
            HStack(spacing: 8) {
                MingCuteIcon(icon).frame(width: 24, height: 24)
                Text(title)
                Spacer(minLength: 0)
            }.modifier(SidebarRowStyle(selected: (store.selection ?? "overview") == selection))
        }.buttonStyle(.plain)
            .accessibilityAddTraits((store.selection ?? "overview") == selection ? .isSelected : [])
    }
}

private struct WindowControls: View {
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 8) {
            control("关闭窗口", color: Color(red: 1, green: 0.37, blue: 0.34), symbol: .close) { $0.performClose(nil) }
            control("最小化窗口", color: Color(red: 1, green: 0.74, blue: 0.18), symbol: .minimize) { $0.miniaturize(nil) }
            control("缩放窗口", color: Color(red: 0.16, green: 0.79, blue: 0.25), symbol: .add) { $0.zoom(nil) }
        }.onHover { hovering = $0 }
    }
    private func control(_ title: String, color: Color, symbol: MingCuteSymbol, action: @escaping (NSWindow) -> Void) -> some View {
        Button {
            if let window = (NSApp.delegate as? AppDelegate)?.window { action(window) }
        } label: {
            Circle().fill(color).frame(width: 12, height: 12)
                .overlay {
                    if hovering { MingCuteIcon(symbol, size: 8).foregroundStyle(.black.opacity(0.65)) }
                }.contentShape(Circle())
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.zoom(nil) }
            else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

private struct SidebarRowStyle: ViewModifier {
    let selected: Bool
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.font(.system(size: 14)).foregroundStyle(selected ? HomeStyle.text : HomeStyle.subtle)
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(selected || hovering ? HomeStyle.fill : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
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
                    MingCuteIcon(.connected, size: 16)
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
                        MingCuteIcon(.search, size: 16).foregroundStyle(HomeStyle.muted)
                        TextField("搜索智能体名称", text: $search).textFieldStyle(.plain)
                            .font(.system(size: 14)).focused(searchFocused)
                            .accessibilityLabel("搜索智能体名称")
                        if !search.isEmpty {
                            Button { search = "" } label: { MingCuteIcon(.clear, size: 16).foregroundStyle(HomeStyle.muted) }
                                .buttonStyle(.plain).accessibilityLabel("清除搜索")
                        }
                    }.padding(.horizontal, 12).frame(width: 320, height: 32)
                        .background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 8))
                    if let error = store.storageError {
                        Label { Text(error) } icon: { MingCuteIcon(.warning, size: 16) }.foregroundStyle(.orange)
                    }
                    if agents.isEmpty {
                        ContentUnavailableView { Label { Text("没有搜索结果") } icon: { MingCuteIcon(.search, size: 48) } } description: { Text("未找到与“\(search)”匹配的智能体。") }.frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(3, max(1, Int((geometry.size.width - 28) / 342)))), alignment: .leading, spacing: 12) {
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
