import SwiftUI

struct NicoRecipe {
    let page: NicoPage
    let variant: NicoVariant
    var node: [String: Any] { page.nodes[variant.root] }
    init(_ component: String, _ properties: [String: String]) {
        guard let (page, variant) = NicoLibrary.component(component, properties: properties) else {
            preconditionFailure("Missing Nico variant \(component): \(properties)")
        }
        self.page = page; self.variant = variant
    }
    func text(_ index: Int? = nil) -> [String: Any]? {
        let node = page.nodes[index ?? variant.root]
        guard node["visible"] as? Bool != false else { return nil }
        if node.string("type") == "TEXT" { return node }
        for child in node["children"] as? [Int] ?? [] { if let text = text(child) { return text } }
        return nil
    }
    func foreground(_ mode: Nico.Mode) -> Color {
        Color(nsColor: text()?.objects("fills").first.map { Nico.paintColor($0, mode: mode) } ?? Nico.nsColor("--color-text", mode: mode))
    }
    /// First visible fill below the root: the slot icon's ink color for icon-only variants.
    func iconForeground(_ mode: Nico.Mode) -> Color {
        var queue = node["children"] as? [Int] ?? []
        while !queue.isEmpty {
            let child = page.nodes[queue.removeFirst()]
            if child["visible"] as? Bool == false { continue }
            if let fill = child.objects("fills").first(where: { $0["visible"] as? Bool != false }) {
                return Color(nsColor: Nico.paintColor(fill, mode: mode))
            }
            queue.append(contentsOf: child["children"] as? [Int] ?? [])
        }
        return foreground(mode)
    }
}

struct NicoSurface: View {
    let node: [String: Any]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let mode = Nico.Mode(dark: scheme == .dark)
        let radius = node.double("cornerRadius", node.double("topLeftRadius"))
        let shape = RoundedRectangle(cornerRadius: radius, style: .circular)
        ZStack {
            ForEach(Array(node.objects("fills").enumerated()), id: \.offset) { _, paint in
                if paint["visible"] as? Bool != false { shape.fill(Color(nsColor: Nico.paintColor(paint, mode: mode))) }
            }
            ForEach(Array(node.objects("strokes").enumerated()), id: \.offset) { _, paint in
                if paint["visible"] as? Bool != false { shape.strokeBorder(Color(nsColor: Nico.paintColor(paint, mode: mode)), lineWidth: node.double("strokeWeight", 1)) }
            }
            ForEach(Array(node.objects("effects").enumerated()), id: \.offset) { _, effect in
                if effect.string("type") == "DROP_SHADOW", effect.double("spread") > 0 {
                    shape.stroke(Color(nsColor: Nico.rgba(Nico.bound(effect, "color", mode: mode) as? [String: Any] ?? [:])), lineWidth: effect.double("spread") * 2)
                }
            }
        }.allowsHitTesting(false)
    }
}

enum NicoSize: String, CaseIterable { case sm, md, lg }
enum NicoButtonKind: String, CaseIterable { case filled, tonal, ghost, plain }
enum NicoButtonColor: String, CaseIterable { case brand, negative, white }

struct NicoButtonStyle: ButtonStyle {
    var color: String = "brand"
    var size: NicoSize = .md
    var kind: String = "filled"
    var capsule = false
    var selected = false
    var loading = false
    func makeBody(configuration: Configuration) -> some View {
        NicoButtonBody(configuration: configuration, style: self)
    }
}
private struct NicoButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: NicoButtonStyle
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let disabled = !enabled
        let loading = enabled && style.loading
        let selected = enabled && !loading && (style.selected || configuration.isPressed)
        let hovered = enabled && !loading && !selected && hover
        let recipe = NicoRecipe("Button", ["color": configuration.role == .destructive ? "negative" : style.color, "size": style.size.rawValue, "kind": style.kind, "capsule": String(style.capsule), "hover": String(hovered), "disabled": String(disabled), "selected": String(selected), "loading": String(loading), "left icon": "false", "right icon": "false"])
        let node = recipe.node
        let mode = Nico.Mode(dark: scheme == .dark)
        HStack(spacing: 4) {
            if style.loading { ProgressView().controlSize(.mini).tint(recipe.foreground(mode)).accessibilityLabel("加载中") }
            configuration.label
        }
        .font(Font(Nico.font(recipe.text() ?? [:], mode: mode)))
        .foregroundStyle(recipe.foreground(mode))
        .padding(.horizontal, node.double("paddingLeft") + node.double("strokeWeight"))
        .frame(height: node.double("height"))
        .background(NicoSurface(node: node))
        .opacity(node.double("opacity", 1))
        .contentShape(RoundedRectangle(cornerRadius: node.double("cornerRadius")))
        .onHover { hover = $0 }
    }
}

/// Icon-only button from the square "Icon button" set; unlike NicoButtonStyle it carries no text padding.
struct NicoIconButtonStyle: ButtonStyle {
    var color: String = "brand"
    var size: NicoSize = .md
    var kind: String = "filled"
    var capsule = false
    var selected = false
    var loading = false
    func makeBody(configuration: Configuration) -> some View {
        NicoIconButtonBody(configuration: configuration, style: self)
    }
}
private struct NicoIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: NicoIconButtonStyle
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Source states are mutually exclusive; at most one axis is true.
        let disabled = !enabled
        let loading = enabled && style.loading
        let selected = enabled && !loading && (style.selected || configuration.isPressed)
        let hovered = enabled && !loading && !selected && hover
        let recipe = NicoRecipe("Icon button", ["color": configuration.role == .destructive ? "negative" : style.color, "size": style.size.rawValue, "kind": style.kind, "capsule": String(style.capsule), "hover": String(hovered), "disabled": String(disabled), "selected": String(selected), "loading": String(loading)])
        let node = recipe.node
        let mode = Nico.Mode(dark: scheme == .dark)
        let ink = recipe.iconForeground(mode)
        ZStack {
            if loading { ProgressView().controlSize(.mini).tint(ink).accessibilityLabel("加载中") }
            else { configuration.label.foregroundStyle(ink) }
        }
        .frame(width: node.double("width"), height: node.double("height"))
        .background(NicoSurface(node: node))
        .opacity(node.double("opacity", 1))
        .contentShape(RoundedRectangle(cornerRadius: node.double("cornerRadius")))
        .onHover { hover = $0 }
    }
}

/// Loading prevents duplicate actions while retaining native focus and keyboard behavior.
struct NicoButton<Label: View>: View {
    var style = NicoButtonStyle()
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    var body: some View {
        Button { if !style.loading { action() } } label: { label() }
            .buttonStyle(style)
            .accessibilityValue(style.loading ? "加载中" : "")
    }
}

struct NicoTag<Label: View>: View {
    var color = "grey"
    var size: NicoSize = .md
    var background = true
    var border = false
    @ViewBuilder var label: () -> Label
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let recipe = NicoRecipe("Tag", ["color": color, "size": size.rawValue, "background": String(background), "border": String(border)])
        let node = recipe.node
        let mode = Nico.Mode(dark: scheme == .dark)
        label().font(Font(Nico.font(recipe.text() ?? [:], mode: mode)))
            .foregroundStyle(recipe.foreground(mode))
            .padding(.horizontal, node.double("paddingLeft") + node.double("strokeWeight"))
            .frame(height: node.double("height"))
            .background(NicoSurface(node: node))
            .accessibilityElement(children: .combine)
    }
}

struct NicoSwitchStyle: ToggleStyle {
    var size: NicoSize = .md
    func makeBody(configuration: Configuration) -> some View { NicoSwitchBody(configuration: configuration, size: size) }
}
private struct NicoSwitchBody: View {
    let configuration: ToggleStyleConfiguration
    let size: NicoSize
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        let recipe = NicoRecipe("Switch", ["size": size.rawValue, "switch": String(configuration.isOn), "disabled": String(!enabled)])
        HStack {
            configuration.label
            Spacer()
            Button { configuration.isOn.toggle() } label: {
                NicoComponent(page: recipe.page, variant: recipe.variant)
                    .overlay(Color.clear.contentShape(Rectangle()))
            }
                .buttonStyle(.plain)
                .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

struct NicoTextField: View {
    var title: String
    @Binding var text: String
    var size: NicoSize = .md
    var negative = false
    var readOnly = false
    var secure = false
    var leadingIcon: MingCuteSymbol? = nil
    var externalFocus: FocusState<Bool>.Binding? = nil
    @FocusState private var focused: Bool
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Source states are mutually exclusive. Disabled/read-only/error precede focus/hover.
        let focused = externalFocus?.wrappedValue ?? focused
        let props = ["size": size.rawValue, "disabled": String(!enabled), "read only": String(enabled && readOnly), "negative": String(enabled && !readOnly && negative), "focused": String(enabled && !readOnly && !negative && focused), "hover": String(enabled && !readOnly && !negative && !focused && hover), "filled": String(!text.isEmpty)]
        let recipe = inputRecipe(props)
        HStack(spacing: 8) {
            if let leadingIcon { MingCuteIcon(leadingIcon, size: 16).foregroundStyle(Nico.color(.colorTextSubtlest)) }
            Group {
                if secure { SecureField(title, text: $text) }
                else { TextField(title, text: $text) }
            }.textFieldStyle(.plain).focused(externalFocus ?? $focused).disabled(readOnly)
            if !text.isEmpty && !readOnly && enabled {
                Button { text = "" } label: {
                    MingCuteIcon(.clear, size: 16)
                        .foregroundStyle(Nico.color(.colorTextSubtlest))
                }
                    .buttonStyle(.plain).accessibilityLabel("清除\(title)")
            }
        }
        .font(Font(Nico.font(size: 14)))
        .padding(.horizontal, 12).frame(height: recipe.node.double("height"))
        .foregroundStyle(Nico.color("--color-text"))
        .background(NicoSurface(node: recipe.node))
        .opacity(recipe.node.double("opacity", 1))
        .onHover { hover = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(negative ? "输入错误" : readOnly ? "只读" : "")
    }
    private func inputRecipe(_ props: [String: String]) -> NicoRecipe {
        // Figma exposes 'read only' under its exact variant-axis spelling.
        let page = NicoLibrary.page("31:6833")
        let set = page.sets.first { $0.name == "Input" }!
        let known = props.filter { set.axes[$0.key] != nil }
        if set.match(known) != nil { return NicoRecipe("Input", known) }
        var relaxed = known; relaxed.removeValue(forKey: "filled")
        if set.match(relaxed) != nil { return NicoRecipe("Input", relaxed) }
        return NicoRecipe("Input", ["size":size.rawValue,"disabled":String(!enabled)])
    }
}

struct NicoProgress: View {
    var value: Double
    var size: NicoSize = .md
    var negative = false
    var body: some View {
        let recipe = NicoRecipe("Progress", ["size":size.rawValue,"complete":String(value >= 1 && !negative),"negative":String(negative)])
        let height = recipe.node.double("height")
        GeometryReader { geometry in
            Capsule().fill(Nico.color("--color-background-neutral-subtle"))
                .overlay(alignment: .leading) {
                    Capsule().fill(Nico.color(negative ? "--color-background-negative-intense" : value >= 1 ? "--color-background-positive-intense" : "--color-background-brand-intense"))
                        .frame(width: geometry.size.width * min(1, max(0, value.isFinite ? value : 0)))
                }
        }.frame(height: height)
            .accessibilityElement().accessibilityLabel("进度")
            .accessibilityValue("\(Int(min(1, max(0, value.isFinite ? value : 0)) * 100))%")
    }
}

/// Shared business-panel surface, using the same border and corner tokens as the overview.
private struct NicoCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Nico.number(.borderRadiusLg))
        content.background(Nico.color(.colorSurface), in: shape)
            .overlay(shape.strokeBorder(Nico.color(.colorBorder), lineWidth: 1))
    }
}

extension View {
    func nicoCard() -> some View { modifier(NicoCardModifier()) }
}
