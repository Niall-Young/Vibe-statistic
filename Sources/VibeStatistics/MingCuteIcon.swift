import SwiftUI

/// Shared catalog for SwiftUI controls and the AppKit status item.
/// Original MingCute artwork and its license are bundled with the app.
enum MingCuteSymbol: String, CaseIterable {
    case overview, settings, search, refresh, connected, sidebar
    case close, minimize, add, clear, warning, alert, time, chart, trend, externalLink

    private static let images: [Self: NSImage] = {
        let resources = Bundle.main.resourceURL?.appendingPathComponent("VibeStatistics_VibeStatistics.bundle")
        let bundle = resources.flatMap(Bundle.init(url:)) ?? Bundle.module
        return Dictionary(uniqueKeysWithValues: allCases.map { symbol in
            guard let url = bundle.url(forResource: symbol.rawValue, withExtension: "svg", subdirectory: "MingCute"),
                  let image = NSImage(contentsOf: url) else {
                preconditionFailure("Missing MingCute resource: \(symbol.rawValue)")
            }
            image.isTemplate = true
            return (symbol, image)
        })
    }()

    var image: NSImage { Self.images[self]! }
}

struct MingCuteIcon: View {
    let symbol: MingCuteSymbol
    var size: CGFloat

    init(_ symbol: MingCuteSymbol, size: CGFloat = 20) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(nsImage: symbol.image).resizable().renderingMode(.template).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}
