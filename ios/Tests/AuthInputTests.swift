import XCTest
@testable import Orbit

final class AuthInputTests: XCTestCase {
    func testEmptyOrIncompleteEmailDoesNotEnableAuthentication() {
        for email in ["", "  ", "person", "person@", "@example.com", "person@example", "person@.com", "person@example..com", "per son@example.com"] {
            XCTAssertFalse(AuthInput.validEmail(email), email)
        }
        for email in ["person@example.com", " person+orbit@sub.example.com "] {
            XCTAssertTrue(AuthInput.validEmail(email), email)
        }
    }
}
