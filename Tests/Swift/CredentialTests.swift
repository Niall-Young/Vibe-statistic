import XCTest
import Security
@testable import VibeStatistics

final class CredentialTests: XCTestCase {
    @MainActor func testPollingRejectsInteractionAndDoesNotTreatDeniedAsMissing() {
        let reader = CredentialReader { query in
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIFail as String)
            return (errSecInteractionNotAllowed, nil)
        }
        XCTAssertThrowsError(try reader.read(.deepseek))
        XCTAssertThrowsError(try reader.read(.deepseek))
        XCTAssertTrue(reader.cache.isEmpty)
    }
    @MainActor func testExplicitAuthorizationIsReusedAcrossRefreshes() throws {
        var calls = 0
        let reader = CredentialReader { query in
            calls += 1
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIAllow as String)
            return (errSecSuccess, Data("test-key".utf8))
        }
        XCTAssertEqual(try reader.read(.deepseek, allowInteraction: true), "test-key")
        for _ in 0..<10 { XCTAssertEqual(try reader.read(.deepseek), "test-key") }
        XCTAssertEqual(calls, 1)
        XCTAssertNil(reader.cache[.qoder])
    }
    @MainActor func testMissingCredentialAllowsExistingCLILogin() throws {
        let reader = CredentialReader { _ in (errSecItemNotFound, nil) }
        XCTAssertNil(try reader.read(.qoder))
    }
}
