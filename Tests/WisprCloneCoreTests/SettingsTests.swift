import XCTest
@testable import WisprCloneCore

final class SettingsTests: XCTestCase {
    override func setUp() { UserDefaults.standard.removeObject(forKey: "mode") }

    func testDefaultsToSmart() {
        XCTAssertEqual(Settings.mode, .smart)
    }

    func testRoundTrips() {
        Settings.mode = .rules
        XCTAssertEqual(Settings.mode, .rules)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "mode"), "rules")
    }
}
