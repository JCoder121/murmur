import XCTest
@testable import WisprCloneCore

final class SettingsTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "mode")
        UserDefaults.standard.removeObject(forKey: "language")
    }

    func testDefaultsToSmart() {
        XCTAssertEqual(Settings.mode, .smart)
    }

    func testRoundTrips() {
        Settings.mode = .rules
        XCTAssertEqual(Settings.mode, .rules)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mode"), "rules")
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
