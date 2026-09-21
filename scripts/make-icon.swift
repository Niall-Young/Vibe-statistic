import AppKit

// Build concatenates NicoSVGPath.swift before this script; only path elements
// with explicit solid fills are accepted, keeping SVG the single source of truth.
final class IconSVG: NSObject, XMLParserDelegate {
    var paths: [(CGPath, CGColor)] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard elementName == "path", let data = attributes["d"], let fill = attributes["fill"], fill.hasPrefix("#"), fill.count == 7,
              let value = UInt32(fill.dropFirst(), radix: 16) else { return }
        paths.append((NicoSVGPath.parse(data), CGColor(red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)))
    }
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/Branding/Creature.svg")
let delegate = IconSVG()
let parser = XMLParser(data: try Data(contentsOf: source)); parser.delegate = delegate
precondition(parser.parse() && delegate.paths.count == 4, "Invalid app icon SVG")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
        for (path, color) in delegate.paths { context.setFillColor(color); context.addPath(path); context.fillPath() }
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
