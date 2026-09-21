import SwiftUI

/// Native, offline inspection surface for the complete exported library.
struct NicoCatalog: View {
    @State private var section = "components"
    @State private var pageID = "13:177"
    @State private var dark = false
    @State private var language = Nico.Language.cn
    @State private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nico Design System").font(.system(size: 24, weight: .semibold))
                    Text("45 个组件集 · 2,506 个变体 · 12 个独立组件 · 360 个变量")
                        .font(.system(size: 12)).foregroundStyle(Nico.color("--color-text-subtle"))
                }
                Spacer()
                Picker("字体模式", selection: $language) { Text("中文").tag(Nico.Language.cn); Text("English").tag(Nico.Language.en) }.frame(width: 120)
                Toggle("深色", isOn: $dark).toggleStyle(.switch)
            }.padding(24)
            Picker("设计规范", selection: $section) {
                Text("组件").tag("components"); Text("变量").tag("variables"); Text("文字样式").tag("text")
                Text("图片与效果").tag("styles"); Text("交互示例").tag("interactive")
            }.pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 16)
            Divider()
            Group {
                switch section {
                case "variables": variables
                case "text": typography
                case "styles": styles
                case "interactive": NicoInteractionDemo()
                default: components
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Nico.color("--color-surface"))
            .foregroundStyle(Nico.color("--color-text"))
            .environment(\.colorScheme, dark ? .dark : .light)
            .preferredColorScheme(dark ? .dark : .light)
    }
    private var mode: Nico.Mode { .init(dark: dark, language: language) }
    private var components: some View {
        HStack(spacing: 0) {
            List(selection: $pageID) {
                ForEach(Nico.inventory, id: \.selfID) { page in
                    HStack {
                        Text(page.string("page"))
                        Spacer()
                        if page.objects("sets").isEmpty && page.objects("single").isEmpty {
                            Text("空").foregroundStyle(.secondary).font(.caption)
                        }
                    }.tag(page.string("id"))
                }
            }.listStyle(.sidebar).frame(width: 180)
            Divider()
            let info = Nico.inventory.first { $0.string("id") == pageID }!
            if info.objects("sets").isEmpty && info.objects("single").isEmpty {
                VStack(spacing: 12) {
                    Text(info.string("page")).font(.title2)
                    Text("Figma 此页面为空，尚无组件或样式定义。")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NicoComponentInspector(page: NicoLibrary.page(pageID), language: language).id(pageID)
            }
        }
    }
    private var variables: some View {
        VStack(spacing: 0) {
            TextField("搜索变量名，例如 color-text、radius", text: $search).textFieldStyle(.roundedBorder).padding(20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Nico.variables.filter { search.isEmpty || $0.string("name").localizedCaseInsensitiveContains(search) }, id: \.selfID) { token in
                        HStack(spacing: 14) {
                            if token.string("resolvedType") == "COLOR" {
                                RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Nico.nsColor(token.string("id"), mode: mode)))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Nico.color("--color-border")))
                                    .frame(width: 40, height: 40)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(token.string("name")).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                Text(valueDescription(token)).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            Text(token.string("resolvedType")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }.padding(.horizontal, 24)
            }
        }
    }
    private func valueDescription(_ token: [String: Any]) -> String {
        let value = Nico.value(token.string("id"), mode: mode)
        if let rgba = value as? [String: Any] {
            return String(format: "rgba(%d, %d, %d, %.3f)", Int((rgba.double("r")*255).rounded()), Int((rgba.double("g")*255).rounded()), Int((rgba.double("b")*255).rounded()), rgba.double("a",1))
        }
        return String(describing: value)
    }
    private var typography: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(Nico.textStyles, id: \.selfID) { style in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(style.string("name")).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        Text(language == .cn ? "让设计与原生体验保持一致 Aa 0123" : "Design feels native. Aa 0123")
                            .nicoTypography(style.string("name"), language: language)
                        Divider()
                    }
                }
            }.padding(24)
        }
    }
    private var styles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("图片样式 · 原始素材").font(.title2)
                HStack(spacing: 24) {
                    ForEach(Nico.paintStyles, id: \.selfID) { style in
                        VStack {
                            if let hash = style.objects("paints").first?.string("imageHash"), let image = NicoImages.image(hash) {
                                Image(nsImage: image).resizable().scaledToFill().frame(width: 64,height:64).clipShape(Circle())
                            }
                            Text(style.string("name")).font(.caption)
                        }
                    }
                }
                Text("效果样式").font(.title2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 32) {
                    ForEach(Nico.effectStyles, id: \.selfID) { style in
                        VStack(spacing: 16) {
                            NicoEffectPreview(style: style, mode: mode).frame(width: 140,height:70)
                            Text(style.string("name")).font(.caption)
                        }.padding(20)
                    }
                }
            }.padding(24)
        }
    }
}
private extension Dictionary where Key == String, Value == Any { var selfID: String { string("id") } }

private struct NicoEffectPreview: View {
    let style: [String: Any]
    let mode: Nico.Mode
    var body: some View {
        let node: [String: Any] = ["type":"RECTANGLE","width":140,"height":70,"cornerRadius":12,"fills":[["type":"SOLID","color":Nico.value("--color-surface-raised",mode:mode)]],"effects":style.objects("effects")]
        NicoArtwork(page: NicoPage(["nodes":[node]]), root: 0, mode: mode)
    }
}

private struct NicoComponentInspector: View {
    let page: NicoPage
    let language: Nico.Language
    @State private var setID = ""
    @State private var variantID = ""
    @State private var batch = 0
    private var set: NicoComponentSet? { page.sets.first { $0.id == setID } ?? page.sets.first }
    private var variants: [NicoVariant] { self.set?.variants ?? page.singles }
    private var current: NicoVariant? { variants.first { $0.id == variantID } ?? variants.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(page.name).font(.title2.weight(.semibold))
                    Spacer()
                    if page.sets.count > 1 {
                        Picker("组件集", selection: Binding(get: { set?.id ?? "" }, set: { setID = $0; variantID = ""; batch = 0 })) {
                            ForEach(page.sets) { Text($0.name).tag($0.id) }
                        }.frame(width: 240)
                    }
                    Text("\(variants.count) 个变体").foregroundStyle(.secondary)
                }
                if let current {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView([.horizontal, .vertical]) {
                            NicoComponent(page: page, variant: current, language: language)
                                .padding(36).frame(minWidth: 280, minHeight: 180)
                        }.frame(minHeight: 200, maxHeight: 380)
                            .background(Nico.color("--color-background-neutral-subtle"), in: RoundedRectangle(cornerRadius: 12))
                        if let set {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(set.axes.keys.sorted(), id: \.self) { key in
                                    Picker(key, selection: Binding(get: { current.properties[key] ?? "" }, set: { change(key, value: $0, current: current, set: set) })) {
                                        ForEach(set.axes[key]!, id: \.self) { Text($0).tag($0) }
                                    }
                                }
                            }.frame(width: 240)
                        }
                    }
                    Text("Figma \(current.id) · \(current.description)").font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    Link("在 Figma 中查看", destination: URL(string: "https://www.figma.com/design/jEAPJHkP5H4FWMoqH8ovYo?node-id=\(current.id.replacingOccurrences(of: ":",with:"-"))")!)
                }
                Divider()
                HStack {
                    Text("全部变体").font(.headline)
                    Spacer()
                    Button("上一页") { batch -= 1 }.disabled(batch == 0)
                    Text("\(batch+1) / \(max(1,(variants.count+23)/24))").monospacedDigit()
                    Button("下一页") { batch += 1 }.disabled((batch+1)*24 >= variants.count)
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(variants.dropFirst(batch*24).prefix(24))) { variant in
                        Button { variantID = variant.id } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                ScrollView(.horizontal) { NicoComponent(page: page, variant: variant, language: language).padding(16) }
                                Text(variant.description).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
                                .background(Nico.color("--color-background-neutral-subtle"),in:RoundedRectangle(cornerRadius:8))
                        }.buttonStyle(.plain)
                    }
                }
                if !page.singles.isEmpty && set != nil {
                    Text("组合组件").font(.headline)
                    ForEach(page.singles) { variant in
                        Text(variant.name).font(.subheadline)
                        ScrollView(.horizontal) { NicoComponent(page:page,variant:variant,language:language).padding(16) }
                    }
                }
            }.padding(24)
        }
    }
    private func change(_ key: String, value: String, current: NicoVariant, set: NicoComponentSet) {
        var properties = current.properties; properties[key] = value
        if let exact = set.match(properties) { variantID = exact.id; return }
        // Some states are intentionally mutually exclusive in Figma; select the closest valid source variant.
        let candidates = set.variants.filter { $0.properties[key] == value }
        variantID = candidates.max { a,b in
            a.properties.filter { current.properties[$0.key] == $0.value }.count < b.properties.filter { current.properties[$0.key] == $0.value }.count
        }?.id ?? current.id
    }
}

private struct NicoInteractionDemo: View {
    @State private var clicks = 0
    @State private var text = ""
    @State private var password = ""
    @State private var enabled = true
    @State private var progress = 0.45
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                Text("原生交互").font(.title2)
                Text("支持键盘焦点、输入、切换与辅助功能；下方交互仅影响此预览。") .foregroundStyle(.secondary)
                HStack(spacing:12) {
                    ForEach(NicoButtonKind.allCases,id:\.self) { kind in
                        Button(kind.rawValue) { clicks += 1 }.buttonStyle(NicoButtonStyle(kind:kind.rawValue))
                    }
                }
                HStack(spacing:12) {
                    ForEach(NicoButtonKind.allCases,id:\.self) { kind in
                        Button { clicks += 1 } label: { MingCuteIcon(.add, size: 16) }
                            .buttonStyle(NicoIconButtonStyle(kind:kind.rawValue)).accessibilityLabel(kind.rawValue)
                    }
                }
                Text("按钮已点击 \(clicks) 次").monospacedDigit()
                HStack(spacing:12) {
                    Button("危险操作") { clicks += 1 }.buttonStyle(NicoButtonStyle(color:"negative"))
                    Button("已禁用") {}.buttonStyle(NicoButtonStyle()).disabled(true)
                    NicoButton(style:.init(loading:true),action:{}) { Text("加载中") }
                }
                NicoTextField(title:"输入文字",text:$text).frame(maxWidth:360)
                NicoTextField(title:"密码",text:$password,secure:true).frame(maxWidth:360)
                NicoTextField(title:"错误状态",text:$text,negative:true).frame(maxWidth:360)
                Toggle("启用预览",isOn:$enabled).toggleStyle(NicoSwitchStyle()).frame(maxWidth:360)
                HStack(spacing:8) {
                    NicoTag(color:"green") { Text("已连接") }
                    NicoTag(color:"orange",size:.lg) { Text("数据已过期") }
                    NicoTag(color:"red",border:true) { Text("错误") }
                }
                NicoProgress(value:progress).frame(maxWidth:360)
                Slider(value:$progress,in:0...1).frame(maxWidth:360).accessibilityLabel("预览进度")
                Text("\(Int(progress*100))%").monospacedDigit()
            }.padding(32).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
