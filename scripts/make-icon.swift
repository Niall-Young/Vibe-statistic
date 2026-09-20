import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let base = NSBezierPath(roundedRect: NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84), xRadius: p * 0.2, yRadius: p * 0.2)
        NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.17, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.08, alpha: 1))!.draw(in: base, angle: -60)
        for (i, height) in [0.24, 0.44, 0.34].enumerated() {
            let rect = NSRect(x: p * (0.25 + Double(i) * 0.18), y: p * 0.28, width: p * 0.12, height: p * height)
            NSColor(calibratedRed: i == 1 ? 0.52 : 0.83, green: i == 1 ? 0.85 : 0.9, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: p * 0.035, yRadius: p * 0.035).fill()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
