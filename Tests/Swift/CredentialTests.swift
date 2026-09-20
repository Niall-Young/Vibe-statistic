import XCTest
import Security
@testable import VibeStatistics

final class CredentialTests: XCTestCase {
    @MainActor func testPollingRejectsInteractionAndDoesNotTreatDeniedAsMissing() {
        var calls = 0
        let reader = CredentialReader { query in
            calls += 1
            var allowed: DarwinBoolean = true
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertFalse(allowed.boolValue)
            XCTAssertEqual(query[kSecUseAuthenticationUI as String] as? String, kSecUseAuthenticationUIFail as String)
            return (errSecInteractionNotAllowed, nil)
        }
        XCTAssertThrowsError(try reader.read(.deepseek))
        XCTAssertThrowsError(try reader.read(.deepseek))
        XCTAssertTrue(reader.cache.isEmpty)
        XCTAssertEqual(calls, 1)
    }
    @MainActor func testExplicitAuthorizationIsReusedAcrossRefreshes() throws {
        var calls = 0
        let reader = CredentialReader { query in
            calls += 1
            var allowed: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&allowed), errSecSuccess)
            XCTAssertTrue(allowed.boolValue)
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
    @MainActor func testLegacyInteractionFlagIsRestoredAfterFailure() throws {
        var original: DarwinBoolean = false
        XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&original), errSecSuccess)
        defer { SecKeychainSetUserInteractionAllowed(original.boolValue) }
        for initial in [true, false] {
            XCTAssertEqual(SecKeychainSetUserInteractionAllowed(initial), errSecSuccess)
            let reader = CredentialReader { _ in (errSecAuthFailed, nil) }
            XCTAssertThrowsError(try reader.read(.deepseek))
            var restored: DarwinBoolean = false
            XCTAssertEqual(SecKeychainGetUserInteractionAllowed(&restored), errSecSuccess)
            XCTAssertEqual(restored.boolValue, initial)
        }
    }
    @MainActor func testExplicitRetryAndSaveClearBlockedState() throws {
        var calls = 0
        let reader = CredentialReader { _ in
            calls += 1
            return calls == 1 ? (errSecInteractionNotAllowed, nil) : (errSecSuccess, Data("test-key".utf8))
        }
        XCTAssertThrowsError(try reader.read(.qoder))
        XCTAssertEqual(try reader.read(.qoder, allowInteraction: true), "test-key")
        XCTAssertEqual(try reader.read(.qoder), "test-key")
        reader.didSave("replacement", for: .qoder)
        XCTAssertEqual(try reader.read(.qoder), "replacement")
        reader.didSave("", for: .qoder)
        XCTAssertNil(try reader.read(.qoder))
        XCTAssertEqual(calls, 2)
    }
    @MainActor func testLiveLegacyCredentialsReturnWithoutInteraction() throws {
        guard ProcessInfo.processInfo.environment["VIBE_LIVE_KEYCHAIN_TEST"] == "1" else {
            throw XCTSkip("Opt-in read-only check against this app's existing credentials")
        }
        let reader = CredentialReader()
        let start = Date()
        for _ in 0..<10 {
            for agent: Agent in [.deepseek, .qoder] {
                do { _ = try reader.read(agent) }
                catch { XCTAssertEqual((error as NSError).domain, NSOSStatusErrorDomain) }
            }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

}
