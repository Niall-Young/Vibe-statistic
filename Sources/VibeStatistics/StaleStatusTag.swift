import SwiftUI

/// Nico Tag, Figma node 85:7740. The icon is the original exported artwork.
struct StaleStatusTag: View {
    private static let icon: NSImage = {
        let resources = Bundle.main.resourceURL?.appendingPathComponent("VibeStatistics_VibeStatistics.bundle")
        let bundle = resources.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: "stale", withExtension: "svg", subdirectory: "StatusTags"),
              let image = NSImage(contentsOf: url) else { preconditionFailure("Missing stale status tag icon") }
        return image
    }()
    var body: some View {
        NicoTag(color: "orange") {
            HStack(spacing: 4) {
                Image(nsImage: Self.icon).resizable().renderingMode(.template)
                    .frame(width: 16, height: 16).accessibilityHidden(true)
                Text("数据已过期")
            }
        }.fixedSize()
    }
}
