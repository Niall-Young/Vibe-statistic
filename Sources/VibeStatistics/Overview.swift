import SwiftUI

// Shared Nico variables resolve their original Light/Dark aliases in AppKit.
enum HomeStyle {
    static let surface = Nico.color(.colorSurface)
    static let text = Nico.color(.colorText)
    static let subtle = Nico.color(.colorTextSubtle)
    static let muted = Nico.color(.colorTextSubtlest)
    static let fill = Nico.color(.colorBackgroundNeutralSubtle)
    static let border = Nico.color(.colorBorder)
    static let positive = Nico.color(.colorTextPositive)
    static let information = Nico.color(.colorTextInformation)
    static let negative = Nico.color(.colorTextNegative)
    static func quotaColor(_ fraction: Double) -> Color {
        fraction <= 0.25 ? negative : fraction < 0.75 ? information : positive
    }
}

// The shell is intentionally custom: NavigationSplitView/List/Toolbar add
// macOS 26 floating glass and system insets that are absent from the design.
struct MainView: View {
    @ObservedObject var store: UsageStore
    @State private var search = ""
    @State private var sidebarVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    private var title: String {
        if store.selection == "settings" { return "设置" }
        return store.selection.flatMap(Agent.init(rawValue:))?.name ?? "总览"
    }
    var body: some View {
        VStack(spacing: 0) {
            // Keep controls in one stable hierarchy: moving them between the
            // sidebar and content header used to double the collapsed inset.
            HStack(spacing: 0) {
                windowHeader
                    .frame(width: sidebarVisible ? 240 : 140, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(HomeStyle.border)
                            .frame(width: 1).opacity(sidebarVisible ? 1 : 0)
                    }
                HStack(spacing: 10) {
                    Text(title).nicoTypography("14/Medium/Default")
                    if let date = store.snapshots.values.compactMap(\.date).max() {
                        Text("数据更新于 \(date.formatted(date: .omitted, time: .shortened))")
                            .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted)
                    }
                    Spacer()
                    Button { store.refresh() } label: {
                        MingCuteIcon(.refresh, size: 16)
                    }.buttonStyle(NicoIconButtonStyle(size: .sm, kind: "plain")).keyboardShortcut("r").help("刷新全部额度 ⌘R")
                        .accessibilityLabel("刷新全部额度").disabled(store.active)
                }.padding(.horizontal, 20).frame(height: 52)
            }.background(WindowDragArea())
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        navigationRow("总览", selection: "overview", icon: .overview)
                        navigationRow("设置", selection: "settings", icon: .settings)
                        HStack {
                            Text("用量详情").nicoTypography("14/Regular/Default").foregroundStyle(HomeStyle.muted)
                            Spacer()
                        }.padding(.leading, 12).padding(.trailing, 5)
                            .frame(height: 22).padding(.top, 16).padding(.bottom, 4)
                        ForEach(store.installedAgents) { agent in
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
                .frame(width: 239)
                .frame(width: sidebarVisible ? 240 : 0, alignment: .leading)
                .clipped()
                .overlay(alignment: .trailing) {
                    Rectangle().fill(HomeStyle.border)
                        .frame(width: 1).opacity(sidebarVisible ? 1 : 0)
                }
                .allowsHitTesting(sidebarVisible)
                .accessibilityHidden(!sidebarVisible)
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
        HStack(spacing: 0) {
            WindowControls().padding(.trailing, 20)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                    sidebarVisible.toggle()
                }
            } label: {
                MingCuteIcon(.sidebar, size: 16)
            }.buttonStyle(NicoIconButtonStyle(size: .sm, kind: "plain")).help(sidebarVisible ? "隐藏边栏" : "显示边栏")
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
        content.nicoTypography("14/Regular/Default").foregroundStyle(selected ? HomeStyle.text : HomeStyle.subtle)
            .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(selected ? HomeStyle.fill : hovering ? Nico.color(.colorBackgroundNeutralSubtleHover) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

struct SegmentedQuotaBar: View {
    let fraction: Double
    var height: CGFloat = 20
    var body: some View {
        GeometryReader { geometry in
            let width = max(0, (geometry.size.width - 38) / 20)
            HStack(spacing: 2) {
                ForEach(0..<20) { index in
                    Rectangle().fill(Nico.color(.colorBackgroundNeutralSubtle))
                        .overlay(alignment: .leading) {
                            Rectangle().fill(HomeStyle.quotaColor(fraction))
                                .frame(width: width * min(1, max(0, fraction * 20 - Double(index))))
                        }.frame(width: width)
                }
            }
        }.frame(height: height).accessibilityHidden(true)
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
            }.nicoTypography("14/Regular/Default").frame(minHeight: 22)
            if let fraction = metric.fraction { SegmentedQuotaBar(fraction: fraction) }
            if let reset = metric.resetAt {
                Text("\(Date(timeIntervalSince1970: reset).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())) \(metric.note == "套餐到期时间" ? "到期" : "重置")\(metric.note?.contains("估算") == true ? "（估算）" : "")")
                    .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}


struct AgentCard: View {
    @ObservedObject var store: UsageStore
    let agent: Agent
    private var overviewMetrics: [UsageMetric] {
        (store.snapshots[agent]?.metrics ?? []).filter { metric in
            // Supplemental Codex credits remain available on the detail screen.
            !(agent == .codex && metric.id.hasSuffix(".credits"))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                AgentLogo(agent: agent, size: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(HomeStyle.border))
                Text(agent.name).nicoTypography("16/Medium/Default").fixedSize()
                Spacer(minLength: 0)
                Text(store.sourceDescription(agent))
                    .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted).lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            if store.snapshots[agent] != nil {
                let metrics = overviewMetrics
                VStack(spacing: 12) {
                    ForEach(Array(metrics.prefix(2))) { HomeMetricRow(metric: $0) }
                    if metrics.count > 2 {
                        Text("另有 \(metrics.count - 2) 项额度与余额")
                            .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂无数据").font(.system(size: 22, weight: .medium))
                    Text(store.refreshing.contains(agent) ? "正在读取额度信息…" : "点击重试以重新连接")
                        .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack {
                StatusLabel(store: store, agent: agent)
                Spacer(minLength: 4)
                if (store.snapshots[agent] != nil && store.stale(agent)) || store.errors[agent] != nil {
                    Button { store.reconnect(agent) } label: {
                        Text(store.refreshing.contains(agent) ? "重试中" : "重试")
                    }.buttonStyle(NicoButtonStyle(kind: "ghost")).disabled(store.refreshing.contains(agent))
                        .accessibilityLabel("重新连接 \(agent.name)")
                }
                Button { store.selection = agent.rawValue } label: {
                    Text("用量详情")
                }.buttonStyle(NicoButtonStyle(kind: "ghost")).accessibilityLabel("查看 \(agent.name) 用量详情")
            }
        }
        .foregroundStyle(HomeStyle.text)
        .padding(20).frame(maxWidth: .infinity, minHeight: 306, alignment: .topLeading)
        .nicoCard()
    }
}

struct OverviewView: View {
    @ObservedObject var store: UsageStore
    @Binding var search: String
    var searchFocused: FocusState<Bool>.Binding
    private var agents: [Agent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.installedAgents.filter { query.isEmpty || "\($0.name) \($0.subtitle)".localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: geometry.size.width >= 900 ? 4 : 2), spacing: 12) {
                        summary("本周 Token 用量", value: tokenValue(.week), unit: "万 token")
                        summary("本月 Token 用量", value: tokenValue(.month), unit: "万 token")
                        summary("总消耗量", value: tokenValue(.allTime), unit: "万 token")
                        summary("当前 Agent", value: "\(store.installedAgents.count)", unit: "个")
                    }
                    NicoTextField(title: "搜索智能体名称", text: $search, leadingIcon: .search, externalFocus: searchFocused)
                        .frame(width: 320)
                    if store.installedAgents.isEmpty {
                        VStack(spacing: 12) {
                            Text("未检测到支持的 Agent").font(.headline)
                            Text("请先安装 Codex、Kimi Code、Qoder CN、Claude Code 或 Antigravity CLI。自定义安装路径可在设置中填写。")
                            HStack {
                                Button("重新检测") { store.detectAgents() }
                                Button("打开设置") { store.selection = "settings" }
                            }
                        }.padding(32).frame(maxWidth: .infinity)
                    } else if agents.isEmpty {
                        ContentUnavailableView { Label { Text("没有搜索结果") } icon: { MingCuteIcon(.search, size: 48) } } description: { Text("未找到与“\(search)”匹配的智能体。") }.frame(maxWidth: .infinity)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(3, max(1, Int((geometry.size.width - 28) / 342)))), alignment: .leading, spacing: 12) {
                            ForEach(agents) { agent in AgentCard(store: store, agent: agent) }
                        }
                    }
                    Text("Token 为本机 Claude Code / DeepSeek 日志的输入 + 输出；本周从周一开始，本月按自然月，总消耗量为现存日志累计，非全部 Agent 用量。")
                        .nicoTypography("12/Regular/Default").foregroundStyle(HomeStyle.muted)
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }.background(HomeStyle.surface)
        }
        // The window's key view loop hands first responder to the search field
        // on every appearance; focus belongs to the user, so resign it.
        .onAppear { DispatchQueue.main.async { searchFocused.wrappedValue = false } }
    }
    private func tokenValue(_ period: LocalUsage.Period) -> String {
        guard let total = store.snapshots[.deepseek]?.localUsage?.tokens(in: period) else { return "—" }
        return (total / 10_000).formatted(.number.locale(Locale(identifier: "zh_CN")).precision(.fractionLength(0...2)))
    }
    private func summary(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).nicoTypography("14/Regular/Default").foregroundStyle(HomeStyle.subtle)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).nicoTypography("28/Bold/Default").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(unit).nicoTypography("16/Regular/Default").foregroundStyle(HomeStyle.subtle).lineLimit(1)
            }.frame(height: 36)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 16)
            .background(HomeStyle.fill, in: RoundedRectangle(cornerRadius: 12))
    }
}
