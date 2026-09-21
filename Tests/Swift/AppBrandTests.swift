import XCTest
import AppKit
@testable import VibeStatistics

final class AppBrandTests: XCTestCase {
    func testMenuIconHasPortableRetinaRepresentationsAndTransparentApertures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image = AppBrand.statusImage(svgURL: root.appendingPathComponent("Resources/Branding/Creature.svg"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        XCTAssertEqual(reps.map(\.pixelsWide), [18, 36])
        for rep in reps {
            var opaque = 0
            var transparent = 0
            for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
                let alpha = try XCTUnwrap(rep.colorAt(x: x, y: y)).alphaComponent
                if alpha > 0.5 { opaque += 1 } else { transparent += 1 }
            } }
            XCTAssertGreaterThan(opaque, rep.pixelsWide * rep.pixelsHigh / 4)
            XCTAssertGreaterThan(transparent, rep.pixelsWide * rep.pixelsHigh / 4)
            let restored = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(rep.representation(using: .png, properties: [:]))))
            XCTAssertEqual(restored.pixelsWide, rep.pixelsWide)
        }
    }
}
