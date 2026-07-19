import XCTest
@testable import WisprCloneCore

final class SettingsTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "language")
    }

    func testLanguageDefaultsToAuto() {
        XCTAssertEqual(Settings.language, .auto)
    }

    func testLanguageRoundTrips() {
        Settings.language = .en
        XCTAssertEqual(Settings.language, .en)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "language"), "en")
    }
}
