import XCTest
@testable import ChirpCore

final class AppContextTests: XCTestCase {
    func testChatApps() {
        XCTAssertEqual(AppContext.bucket(for: "Slack"), .chat)
        XCTAssertEqual(AppContext.bucket(for: "Messages"), .chat)
        XCTAssertEqual(AppContext.bucket(for: "Discord"), .chat)
    }

    func testCodeApps() {
        XCTAssertEqual(AppContext.bucket(for: "Terminal"), .code)
        XCTAssertEqual(AppContext.bucket(for: "iTerm2"), .code)
        XCTAssertEqual(AppContext.bucket(for: "Visual Studio Code"), .code)
        XCTAssertEqual(AppContext.bucket(for: "Ghostty"), .code)
    }

    func testEverythingElseIsProse() {
        XCTAssertEqual(AppContext.bucket(for: "Notion"), .prose)
        XCTAssertEqual(AppContext.bucket(for: "Safari"), .prose)
        XCTAssertEqual(AppContext.bucket(for: ""), .prose)
    }

    func testStructCarriesBucket() {
        let ctx = AppContext(appName: "Slack", windowTitle: "#general")
        XCTAssertEqual(ctx.bucket, .chat)
    }
}
