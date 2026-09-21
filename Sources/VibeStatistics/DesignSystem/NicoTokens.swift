import AppKit
import SwiftUI
import CoreText

/// Original Figma values, including aliases. No CSS engine or WebView is involved.
enum Nico {
    static let bundle: Bundle = {
        let embedded = Bundle.main.resourceURL?.appendingPathComponent("VibeStatistics_VibeStatistics.bundle")
        return embedded.flatMap(Bundle.init(url:)) ?? Bundle.module
    }()
    static let foundations = object("foundations")
    static let variables = foundations["variables"] as! [[String: Any]]
    static let collections = foundations["collections"] as! [[String: Any]]
    static let byID = Dictionary(uniqueKeysWithValues: variables.map { ($0["id"] as! String, $0) })
    static let byName = Dictionary(uniqueKeysWithValues: variables.map { (($0["name"] as! String).components(separatedBy: "/").last!, $0) })
    static let textStyles = foundations["textStyles"] as! [[String: Any]]
    static let paintStyles = foundations["paintStyles"] as! [[String: Any]]
    static let effectStyles = foundations["effectStyles"] as! [[String: Any]]
    static let inventory = array("inventory")

    enum Language: String, CaseIterable { case cn = "CN", en = "EN" }
    struct Mode {
        var dark = false
        var language: Language = .cn
    }
    enum ResolutionError: Error { case unknown(String), cyclic(String), missingMode(String) }

    static func resource(_ name: String, extension ext: String = "json") -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Nico") else {
            preconditionFailure("Missing bundled Nico resource: \(name).\(ext)")
        }
        return url
    }
    static func object(_ name: String) -> [String: Any] {
        do { return try JSONSerialization.jsonObject(with: Data(contentsOf: resource(name))) as! [String: Any] }
        catch { preconditionFailure("Invalid Nico resource \(name): \(error)") }
    }
    static func array(_ name: String) -> [[String: Any]] {
        do { return try JSONSerialization.jsonObject(with: Data(contentsOf: resource(name))) as! [[String: Any]] }
        catch { preconditionFailure("Invalid Nico resource \(name): \(error)") }
    }

    /// Resolves every alias using the target collection's mode, never the source mode ID.
    static func resolve(_ nameOrID: String, mode: Mode = Mode(), visited: Set<String> = []) throws -> Any {
        guard let variable = byID[nameOrID] ?? byName[nameOrID] else { throw ResolutionError.unknown(nameOrID) }
        let id = variable["id"] as! String
        guard !visited.contains(id) else { throw ResolutionError.cyclic(id) }
        guard let collection = collections.first(where: { ($0["id"] as? String) == (variable["variableCollectionId"] as? String) }),
              let modes = collection["modes"] as? [[String: String]],
              let values = variable["valuesByMode"] as? [String: Any] else { throw ResolutionError.missingMode(id) }
        let desired = (collection["name"] as? String) == "Typography" ? mode.language.rawValue : (mode.dark ? "Dark" : "Light")
        let modeID = modes.first(where: { $0["name"] == desired })?["modeId"] ?? (collection["defaultModeId"] as! String)
        guard let value = values[modeID] else { throw ResolutionError.missingMode(id) }
        // Color-with-opacity values nest the alias under "color" and carry a percent alpha.
        if let composite = value as? [String: Any],
           let colorAlias = composite["color"] as? [String: String], colorAlias["type"] == "VARIABLE_ALIAS", let target = colorAlias["id"] {
            var color = try resolve(target, mode: mode, visited: visited.union([id])) as? [String: Any] ?? [:]
            if let percent = composite["opacity"] as? NSNumber { color["a"] = percent.doubleValue / 100 }
            return color
        }
        if let alias = value as? [String: String], alias["type"] == "VARIABLE_ALIAS", let target = alias["id"] {
            return try resolve(target, mode: mode, visited: visited.union([id]))
        }
        return value
    }
    static func value(_ name: String, mode: Mode = Mode()) -> Any {
        do { return try resolve(name, mode: mode) } catch { preconditionFailure("Unresolved Nico token \(name): \(error)") }
    }
    static func number(_ name: String, mode: Mode = Mode()) -> CGFloat { (value(name, mode: mode) as! NSNumber).doubleValue }
    static func rgba(_ value: [String: Any]) -> NSColor {
        NSColor(srgbRed: value.double("r"), green: value.double("g"), blue: value.double("b"), alpha: value.double("a", 1))
    }
    static func nsColor(_ name: String, mode: Mode) -> NSColor { rgba(value(name, mode: mode) as! [String: Any]) }
    static func color(_ name: String) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            nsColor(name, mode: Mode(dark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua))
        })
    }
    static func bound(_ object: [String: Any], _ key: String, mode: Mode) -> Any? {
        if let bindings = object["boundVariables"] as? [String: Any],
           let alias = bindings[key] as? [String: String], let id = alias["id"] {
            return try? resolve(id, mode: mode)
        }
        return object[key]
    }
    static func paintColor(_ paint: [String: Any], mode: Mode) -> NSColor {
        if let bindings = paint["boundVariables"] as? [String: Any], bindings["color"] != nil {
            // Figma exposes an alias's alpha again as paint.opacity; do not multiply it twice.
            return rgba(bound(paint, "color", mode: mode) as? [String: Any] ?? [:])
        }
        let color = rgba(paint["color"] as? [String: Any] ?? [:])
        return color.withAlphaComponent(color.alphaComponent * paint.double("opacity", 1))
    }
    static let registerFonts: Void = {
        for name in ["Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold"] {
            if let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Nico/Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()
    static func font(size: CGFloat, weight: CGFloat = 400, language: Language = .cn) -> NSFont {
        _ = registerFonts
        let style = weight >= 600 ? "Semibold" : weight >= 500 ? "Medium" : "Regular"
        let name = language == .cn ? "PingFangSC-\(style)" : "Poppins-\(style == "Semibold" ? "SemiBold" : style)"
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular)
    }
    static func font(_ style: [String: Any], mode: Mode) -> NSFont {
        let size = (bound(style, "fontSize", mode: mode) as? NSNumber)?.doubleValue ?? 14
        let weight = (bound(style, "fontWeight", mode: mode) as? NSNumber)?.doubleValue ?? 400
        return font(size: size, weight: weight, language: mode.language)
    }
}

extension Dictionary where Key == String, Value == Any {
    func double(_ key: String, _ fallback: Double = 0) -> Double { (self[key] as? NSNumber)?.doubleValue ?? fallback }
    func string(_ key: String, _ fallback: String = "") -> String { self[key] as? String ?? fallback }
    func objects(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}

struct NicoTypography: ViewModifier {
    let name: String
    var language: Nico.Language = .cn
    func body(content: Content) -> some View {
        let style = Nico.textStyles.first { $0.string("name") == name }!
        let font = Nico.font(style, mode: .init(language: language))
        let lineHeight = (Nico.bound(style, "lineHeight", mode: .init(language: language)) as? NSNumber)?.doubleValue
            ?? (style["lineHeight"] as? [String: Any])?.double("value") ?? font.pointSize
        content.font(Font(font)).lineSpacing(max(0, lineHeight - font.ascender + font.descender))
    }
}

extension View {
    func nicoTypography(_ name: String = "14/Regular/Default", language: Nico.Language = .cn) -> some View {
        modifier(NicoTypography(name: name, language: language))
    }
}
