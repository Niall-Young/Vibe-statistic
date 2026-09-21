import AppKit

/// Render explicit 1x/2x template representations from the editable SVG source.
enum AppBrand {
    private final class Paths: NSObject, XMLParserDelegate {
        var paths: [CGPath] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if elementName == "path", let data = attributes["d"] { paths.append(NicoSVGPath.parse(data)) }
        }
    }
    static var statusImage: NSImage {
        statusImage(svgURL: Bundle.main.resourceURL!.appendingPathComponent("Branding/Creature.svg"))
    }
    static func statusImage(svgURL: URL) -> NSImage {
        let parsed = Paths()
        if let data = try? Data(contentsOf: svgURL) {
            let parser = XMLParser(data: data); parser.delegate = parsed; _ = parser.parse()
        }
        guard parsed.paths.count == 4 else { return MingCuteSymbol.chart.image }
        let shape = CGMutablePath()
        for path in parsed.paths.dropFirst() { shape.addPath(path) }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for scale in [1, 2] {
            let pixels = 18 * scale
            guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            context.translateBy(x: 1, y: 17)
            context.scaleBy(x: 16.0 / 576.0, y: -16.0 / 576.0)
            context.translateBy(x: -224, y: -224)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(shape); context.fillPath(using: .evenOdd)
            guard let raster = context.makeImage() else { continue }
            let rep = NSBitmapImageRep(cgImage: raster)
            rep.size = image.size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }
}
