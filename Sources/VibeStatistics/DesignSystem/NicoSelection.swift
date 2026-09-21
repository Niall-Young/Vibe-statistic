import SwiftUI

/// Real selection controls, styled with the imported Select and Segmented recipes.
struct NicoOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var id: Value { value }
}

private struct NicoSegmentStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        NicoSegmentBody(configuration: configuration, selected: selected)
    }
}

private struct NicoSegmentBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let recipe = NicoRecipe("Segmented item", ["size": "md", "selected": String(selected), "label": "true", "icon": "false", "hover": String(enabled && hovering && !selected), "disabled": String(!enabled)])
        configuration.label
            .font(Font(Nico.font(recipe.text() ?? [:], mode: .init(dark: scheme == .dark))))
            .foregroundStyle(recipe.foreground(.init(dark: scheme == .dark)))
            .padding(.horizontal, recipe.node.double("paddingLeft") + 1)
            .frame(maxWidth: .infinity).frame(height: recipe.node.double("height"))
            .background(NicoSurface(node: recipe.node))
            .contentShape(Rectangle())
            .opacity(recipe.node.double("opacity", 1))
            .onHover { hovering = $0 }
    }
}

struct NicoSegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NicoOption<Value>]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button(option.title) { selection = option.value }
                    .buttonStyle(NicoSegmentStyle(selected: selection == option.value))
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .background(NicoSurface(node: NicoRecipe("Segmented", [:]).node))
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

struct NicoSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NicoOption<Value>]
    @State private var expanded = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let recipe = NicoRecipe("Select", ["size": "md", "filled": "true", "hover": String(enabled && hovering && !expanded), "focused": String(enabled && expanded), "read only": "false", "disabled": String(!enabled), "clear all": String(!enabled), "negative": "false"])
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Text(options.first { $0.value == selection }?.title ?? title).lineLimit(1)
                Spacer(minLength: 12)
                // Original Select chevron, exported in its own 16-point instance.
                NicoArtwork(page: NicoSelectionArtwork.chevron, root: 7, mode: .init(dark: scheme == .dark))
                    .frame(width: 16, height: 16).accessibilityHidden(true)
            }
            .nicoTypography("14/Regular/Default")
            .foregroundStyle(Nico.color(enabled ? .colorText : .colorTextDisabled))
            .padding(.horizontal, 12).frame(height: recipe.node.double("height"))
            .background(NicoSurface(node: recipe.node))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(options.first { $0.value == selection }?.title ?? "")
        .popover(isPresented: $expanded, arrowEdge: .bottom) {
            NicoMenu(title: title, selection: $selection, options: options) { expanded = false }
        }
    }
}

/// The exported Dropdown → Menu, used as the Select's option list.
struct NicoMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [NicoOption<Value>]
    var dismiss: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let node = NicoRecipe("Menu", [:]).node
        VStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option.value
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(option.title).lineLimit(1)
                        Spacer(minLength: 8)
                        if selection == option.value {
                            // Original Menu item check, exported in its own 16-point instance.
                            NicoArtwork(page: NicoSelectionArtwork.check, root: 8, mode: .init(dark: scheme == .dark))
                                .frame(width: 16, height: 16).accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(NicoMenuItemStyle(selected: selection == option.value))
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }
        .padding(node.double("paddingTop"))
        .frame(width: node.double("width"))
        .background(NicoSurface(node: node))
        .accessibilityElement(children: .contain).accessibilityLabel(title)
    }
}

private struct NicoMenuItemStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View { NicoMenuItemBody(configuration: configuration, selected: selected) }
}

private struct NicoMenuItemBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let recipe = NicoRecipe("Menu item", ["size": "md", "selected": String(selected), "hover": String(enabled && hovering), "disabled": String(!enabled)])
        let mode = Nico.Mode(dark: scheme == .dark)
        configuration.label
            .font(Font(Nico.font(recipe.text() ?? [:], mode: mode)))
            .foregroundStyle(recipe.foreground(mode))
            .padding(.horizontal, recipe.node.double("paddingLeft"))
            .frame(maxWidth: .infinity).frame(height: recipe.node.double("height"))
            .background(NicoSurface(node: recipe.node))
            .contentShape(Rectangle())
            .opacity(recipe.node.double("opacity", 1))
            .onHover { hovering = $0 }
    }
}

struct NicoSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).nicoTypography("16/Medium/Default")
            content()
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).nicoCard()
    }
}

private enum NicoSelectionArtwork {
    static let chevron: NicoPage = {
        var nodes = NicoLibrary.page("31:6845").nodes
        // Detach the original icon from the Select row's x/y layout translation.
        nodes[7]["relativeTransform"] = [[1.0, 0, 0], [0, 1.0, 0]]
        return NicoPage(["page": "Select chevron", "nodes": nodes])
    }()
    static let check: NicoPage = {
        var nodes = NicoLibrary.page("31:6830").nodes
        // Detach the original icon from the Menu item row's x/y layout translation.
        nodes[8]["relativeTransform"] = [[1.0, 0, 0], [0, 1.0, 0]]
        return NicoPage(["page": "Menu item check", "nodes": nodes])
    }()
}
