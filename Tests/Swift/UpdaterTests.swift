import XCTest
@testable import VibeStatistics

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(AppUpdater.isNewer("0.2.0", than: "0.1.0"))
        XCTAssertTrue(AppUpdater.isNewer("0.1.1", than: "0.1.0"))
        XCTAssertTrue(AppUpdater.isNewer("1.0.0", than: "0.9.9"))
        XCTAssertTrue(AppUpdater.isNewer("v0.1.1", than: "0.1.0"))
        XCTAssertTrue(AppUpdater.isNewer("0.1.0.1", than: "0.1.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.0.9", than: "0.1.0"))
        XCTAssertFalse(AppUpdater.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(AppUpdater.isNewer("v0.1.0", than: "v0.2.0"))
    }
}
