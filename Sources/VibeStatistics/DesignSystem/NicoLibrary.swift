import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins

/// A component recipe is a native layer tree, shared by its Figma variants.
/// Nodes are interned on export so repeated icon and label geometry is stored once.
final class NicoPage {
    let name: String
    let nodes: [[String: Any]]
    let sets: [NicoComponentSet]
    let singles: [NicoVariant]
    init(_ data: [String: Any]) {
        name = data.string("page")
        nodes = data.objects("nodes")
        sets = data.objects("sets").map(NicoComponentSet.init)
        singles = data.objects("single").map(NicoVariant.init)
    }
}
struct NicoVariant: Identifiable {
    let id: String
    let name: String
    let properties: [String: String]
    let root: Int
    init(_ data: [String: Any]) {
        id = data.string("id"); name = data.string("name")
        properties = data["properties"] as? [String: String] ?? [:]
        root = Int(data.double("root"))
    }
    var description: String {
        properties.isEmpty ? name : properties.keys.sorted().map { "\($0)=\(properties[$0]!)" }.joined(separator: ", ")
    }
}
struct NicoComponentSet: Identifiable {
    let id: String
    let name: String
    let variants: [NicoVariant]
    init(_ data: [String: Any]) {
        id = data.string("id"); name = data.string("name")
        variants = data.objects("variants").map(NicoVariant.init)
    }
    var axes: [String: [String]] {
        var result: [String: Set<String>] = [:]
        for variant in variants { for (key, value) in variant.properties { result[key, default: []].insert(value) } }
        return result.mapValues { $0.sorted() }
    }
    func match(_ properties: [String: String]) -> NicoVariant? {
        variants.first { variant in properties.allSatisfy { variant.properties[$0.key] == $0.value } }
    }
}

enum NicoLibrary {
    private static var cache: [String: NicoPage] = [:]
    static func page(_ id: String) -> NicoPage {
        if let page = cache[id] { return page }
        let page = NicoPage(Nico.object("components-" + id.replacingOccurrences(of: ":", with: "-")))
        cache[id] = page
        return page
    }
    static func component(_ name: String, properties: [String: String] = [:]) -> (NicoPage, NicoVariant)? {
        for item in Nico.inventory {
            if item.objects("sets").contains(where: { $0.string("name") == name }) {
                let page = page(item.string("id"))
                if let variant = page.sets.first(where: { $0.name == name })?.match(properties) { return (page, variant) }
            }
            if item.objects("single").contains(where: { $0.string("name") == name }) {
                let page = page(item.string("id"))
                if let variant = page.singles.first(where: { $0.name == name }) { return (page, variant) }
            }
        }
        return nil
    }
}

/// Every source component/variant is available as a SwiftUI view, drawn by AppKit.
/// Interactive controls compose this artwork with native Button/TextField/Toggle.
struct NicoComponent: View {
    let page: NicoPage
    let variant: NicoVariant
    var language: Nico.Language = .cn
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let root = page.nodes[variant.root]
        NicoArtwork(page: page, root: variant.root, mode: .init(dark: colorScheme == .dark, language: language))
            .frame(width: root.double("width"), height: root.double("height"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(variant.description)
    }
}

struct NicoArtwork: NSViewRepresentable {
    let page: NicoPage
    let root: Int
    var mode: Nico.Mode
    var omitText = false
    func makeNSView(context: Context) -> NicoDrawingView { NicoDrawingView() }
    func updateNSView(_ view: NicoDrawingView, context: Context) {
        view.page = page; view.root = root; view.mode = mode; view.omitText = omitText; view.needsDisplay = true
    }
}

final class NicoDrawingView: NSView {
    var page: NicoPage?
    var root = 0
    var mode = Nico.Mode()
    var omitText = false
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let page, let context = NSGraphicsContext.current?.cgContext else { return }
        let node = page.nodes[root]
        context.saveGState()
        context.scaleBy(x: bounds.width / max(1, node.double("width")), y: bounds.height / max(1, node.double("height")))
        draw(root, context: context)
        context.restoreGState()
    }
    private func draw(_ index: Int, context: CGContext) {
        guard let page else { return }
        let node = page.nodes[index]
        guard node["visible"] as? Bool != false else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if let matrix = node["relativeTransform"] as? [[Double]], matrix.count == 2 {
            context.concatenate(CGAffineTransform(a: matrix[0][0], b: matrix[1][0], c: matrix[0][1], d: matrix[1][1], tx: matrix[0][2], ty: matrix[1][2]))
        }
        context.setAlpha(node.double("opacity", 1))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        let rect = CGRect(x: 0, y: 0, width: node.double("width"), height: node.double("height"))
        let path = shape(node, rect: rect)
        for effect in node.objects("effects") where effect["visible"] as? Bool != false && effect.string("type") == "DROP_SHADOW" {
            context.saveGState()
            let offset = effect["offset"] as? [String: Any] ?? [:]
            let color = Nico.rgba(Nico.bound(effect, "color", mode: mode) as? [String: Any] ?? [:])
            let spread = effect.double("spread")
            context.setShadow(offset: CGSize(width: offset.double("x"), height: offset.double("y")), blur: effect.double("radius") / 2, color: color.cgColor)
            context.addPath(path)
            context.setFillColor(color.cgColor)
            if spread > 0 { context.setLineWidth(spread * 2); context.setStrokeColor(color.cgColor); context.drawPath(using: .fillStroke) }
            else { context.fillPath() }
            context.restoreGState()
        }
        if node.string("type") == "TEXT" {
            if !omitText { drawText(node, rect: rect) }
            return
        }
        for paint in node.objects("fills").reversed() where paint["visible"] as? Bool != false {
            context.saveGState(); context.addPath(path); context.clip(using: .evenOdd)
            drawPaint(paint, rect: rect, context: context)
            context.restoreGState()
        }
        if node["clipsContent"] as? Bool == true { context.addPath(path); context.clip() }
        if node.string("type") != "BOOLEAN_OPERATION" {
            for child in node["children"] as? [Int] ?? [] { draw(child, context: context) }
        }
        for paint in node.objects("strokes").reversed() where paint["visible"] as? Bool != false {
            context.saveGState()
            if node["strokeWeight"] == nil {
                let edges = ["strokeTopWeight", "strokeRightWeight", "strokeBottomWeight", "strokeLeftWeight"]
                for (index, edge) in edges.enumerated() {
                    let weight = (Nico.bound(node, edge, mode: mode) as? NSNumber)?.doubleValue ?? 0
                    guard weight > 0 else { continue }
                    context.setStrokeColor(Nico.paintColor(paint, mode: mode).cgColor); context.setLineWidth(weight)
                    let lines = [(CGPoint(x:0,y:weight/2),CGPoint(x:rect.width,y:weight/2)),
                                 (CGPoint(x:rect.width-weight/2,y:0),CGPoint(x:rect.width-weight/2,y:rect.height)),
                                 (CGPoint(x:0,y:rect.height-weight/2),CGPoint(x:rect.width,y:rect.height-weight/2)),
                                 (CGPoint(x:weight/2,y:0),CGPoint(x:weight/2,y:rect.height))]
                    context.move(to: lines[index].0); context.addLine(to: lines[index].1); context.strokePath()
                }
                context.restoreGState(); continue
            }
            let weight = node.double("strokeWeight", 1)
            context.setStrokeColor(Nico.paintColor(paint, mode: mode).cgColor)
            context.setLineWidth(weight)
            if let dash = node["dashPattern"] as? [CGFloat], !dash.isEmpty { context.setLineDash(phase: 0, lengths: dash) }
            context.setLineCap(node.string("strokeCap") == "ROUND" ? .round : .butt)
            context.setLineJoin(node.string("strokeJoin") == "ROUND" ? .round : .miter)
            if node.string("strokeAlign") == "INSIDE" && node.string("type") != "LINE" {
                context.addPath(path); context.clip(); context.setLineWidth(weight * 2)
            } else if node.string("strokeAlign") == "OUTSIDE" {
                let clip = CGMutablePath(); clip.addRect(rect.insetBy(dx: -weight * 2, dy: -weight * 2)); clip.addPath(path)
                context.addPath(clip); context.clip(using: .evenOdd); context.setLineWidth(weight * 2)
            }
            context.addPath(path); context.strokePath(); context.restoreGState()
        }
    }
    private func shape(_ node: [String: Any], rect: CGRect) -> CGPath {
        if node.string("type") == "BOOLEAN_OPERATION", let page {
            let combined = CGMutablePath()
            for index in node["children"] as? [Int] ?? [] {
                let child = page.nodes[index]
                guard child["visible"] as? Bool != false else { continue }
                let matrix = child["relativeTransform"] as? [[Double]] ?? [[1,0,0],[0,1,0]]
                let transform = CGAffineTransform(a:matrix[0][0],b:matrix[1][0],c:matrix[0][1],d:matrix[1][1],tx:matrix[0][2],ty:matrix[1][2])
                combined.addPath(shape(child, rect: CGRect(x:0,y:0,width:child.double("width"),height:child.double("height"))), transform:transform)
            }
            // Boolean children retain their source coordinate origin in the Plugin API.
            // Normalize the combined geometry to the boolean node's local bounding box.
            let bounds = combined.boundingBoxOfPath
            var transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            return combined.copy(using: &transform) ?? combined
        }
        if !node.objects("vectorPaths").isEmpty {
            let result = CGMutablePath()
            for vector in node.objects("vectorPaths") { result.addPath(NicoSVGPath.parse(vector.string("data"))) }
            return result
        }
        if node.string("type") == "ELLIPSE" {
            if let arc = node["arcData"] as? [String: Any], arc.double("innerRadius") > 0 || abs(arc.double("endingAngle") - arc.double("startingAngle")) < 6.28 {
                let path = CGMutablePath(); let center = CGPoint(x: rect.midX, y: rect.midY)
                let radius = min(rect.width, rect.height) / 2, inner = radius * arc.double("innerRadius")
                let start = arc.double("startingAngle"), end = arc.double("endingAngle")
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                if inner > 0 { path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true) }
                else { path.addLine(to: center) }
                path.closeSubpath(); return path
            }
            return CGPath(ellipseIn: rect, transform: nil)
        }
        if node.string("type") == "LINE" { let p = CGMutablePath(); p.move(to: .zero); p.addLine(to: CGPoint(x: rect.width, y: rect.height)); return p }
        let limit = min(rect.width, rect.height) / 2
        let tl = min(node.double("topLeftRadius",node.double("cornerRadius")),limit)
        let tr = min(node.double("topRightRadius",node.double("cornerRadius")),limit)
        let bl = min(node.double("bottomLeftRadius",node.double("cornerRadius")),limit)
        let br = min(node.double("bottomRightRadius",node.double("cornerRadius")),limit)
        let p = CGMutablePath(), w = rect.width, h = rect.height
        p.move(to:CGPoint(x:tl,y:0)); p.addLine(to:CGPoint(x:w-tr,y:0))
        p.addArc(tangent1End:CGPoint(x:w,y:0),tangent2End:CGPoint(x:w,y:tr),radius:tr)
        p.addLine(to:CGPoint(x:w,y:h-br)); p.addArc(tangent1End:CGPoint(x:w,y:h),tangent2End:CGPoint(x:w-br,y:h),radius:br)
        p.addLine(to:CGPoint(x:bl,y:h)); p.addArc(tangent1End:CGPoint(x:0,y:h),tangent2End:CGPoint(x:0,y:h-bl),radius:bl)
        p.addLine(to:CGPoint(x:0,y:tl)); p.addArc(tangent1End:CGPoint(x:0,y:0),tangent2End:CGPoint(x:tl,y:0),radius:tl)
        p.closeSubpath(); return p
    }
    private func drawPaint(_ paint: [String: Any], rect: CGRect, context: CGContext) {
        switch paint.string("type") {
        case "SOLID": context.setFillColor(Nico.paintColor(paint, mode: mode).cgColor); context.fill(rect)
        case "IMAGE":
            if let image = NicoImages.image(paint.string("imageHash"), saturation: (paint["filters"] as? [String:Any])?.double("saturation") ?? 0) { image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: paint.double("opacity", 1), respectFlipped: true, hints: nil) }
        case "GRADIENT_LINEAR", "GRADIENT_RADIAL", "GRADIENT_ANGULAR", "GRADIENT_DIAMOND":
            let stops = paint.objects("gradientStops")
            let colors = stops.map { Nico.rgba($0["color"] as? [String: Any] ?? [:]).cgColor }
            let locations = stops.map { CGFloat($0.double("position")) }
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) else { return }
            let matrix = paint["gradientTransform"] as? [[Double]] ?? [[1,0,0],[0,1,0]]
            let inverse = CGAffineTransform(a: matrix[0][0], b: matrix[1][0], c: matrix[0][1], d: matrix[1][1], tx: matrix[0][2], ty: matrix[1][2]).inverted()
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { let p = CGPoint(x:x,y:y).applying(inverse); return CGPoint(x:p.x*rect.width,y:p.y*rect.height) }
            if paint.string("type") == "GRADIENT_LINEAR" { context.drawLinearGradient(gradient, start: point(0,0.5), end: point(1,0.5), options: [.drawsBeforeStartLocation,.drawsAfterEndLocation]) }
            else { context.drawRadialGradient(gradient, startCenter: point(0.5,0.5), startRadius: 0, endCenter: point(0.5,0.5), endRadius: max(rect.width,rect.height)/2, options: [.drawsAfterEndLocation]) }
        default: break
        }
    }
    private func drawText(_ node: [String: Any], rect: CGRect) {
        let text = node.string("characters")
        let font = Nico.font(node, mode: mode)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ["CENTER": NSTextAlignment.center, "RIGHT": .right, "JUSTIFIED": .justified][node.string("textAlignHorizontal")] ?? .left
        let line = (Nico.bound(node, "lineHeight", mode: mode) as? NSNumber)?.doubleValue ?? (node["lineHeight"] as? [String: Any])?.double("value") ?? 0
        if line > 0 { paragraph.minimumLineHeight = line; paragraph.maximumLineHeight = line }
        paragraph.paragraphSpacing = node.double("paragraphSpacing")
        let color = node.objects("fills").first.map { Nico.paintColor($0, mode: mode) } ?? Nico.nsColor("--color-text", mode: mode)
        let string = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        for segment in node.objects("segments") {
            let range = NSRange(location: Int(segment.double("start")), length: Int(segment.double("end") - segment.double("start")))
            guard NSMaxRange(range) <= string.length else { continue }
            let segFont = Nico.font(segment, mode: mode)
            string.addAttribute(.font, value: segFont, range: range)
            if let fill = segment.objects("fills").first { string.addAttribute(.foregroundColor, value: Nico.paintColor(fill, mode: mode), range: range) }
            if segment.string("textDecoration") == "UNDERLINE" { string.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if let spacing = segment["letterSpacing"] as? [String: Any] {
                string.addAttribute(.kern, value: spacing.double("value") * (spacing.string("unit") == "PERCENT" ? segFont.pointSize / 100 : 1), range: range)
            }
        }
        let size = string.boundingRect(with: CGSize(width: rect.width + 0.5, height: 10000), options: [.usesLineFragmentOrigin,.usesFontLeading]).size
        let y = node.string("textAlignVertical") == "CENTER" ? max(0,(rect.height-size.height)/2) : node.string("textAlignVertical") == "BOTTOM" ? max(0,rect.height-size.height) : 0
        string.draw(with: CGRect(x: 0, y: y, width: rect.width + 0.5, height: max(rect.height,size.height)), options: [.usesLineFragmentOrigin,.usesFontLeading])
    }
}

enum NicoImages {
    private static var cache: [String: NSImage] = [:]
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func image(_ hash: String, saturation: Double = 0) -> NSImage? {
        let key = hash + ":" + String(saturation)
        if let image = cache[key] { return image }
        guard let url = Nico.bundle.url(forResource: hash, withExtension: "png", subdirectory: "Nico/Images"), let image = NSImage(contentsOf: url) else { return nil }
        if saturation != 0, let cgImage = image.cgImage(forProposedRect:nil,context:nil,hints:nil) {
            let filter = CIFilter.colorControls(); filter.inputImage = CIImage(cgImage:cgImage); filter.saturation = Float(1+saturation)
            if let output = filter.outputImage, let cg = context.createCGImage(output,from:output.extent) {
                let adjusted = NSImage(cgImage:cg,size:image.size); cache[key] = adjusted; return adjusted
            }
        }
        cache[key] = image; return image
    }
}
