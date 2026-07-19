import XCTest
@testable import WisprCloneCore

final class WhisperBodyTests: XCTestCase {
    private func bodyString(prompt: String) -> String {
        let body = WhisperServer.multipartBody(
            boundary: "B", wavData: Data("RIFF".utf8), language: .en, prompt: prompt)
        return String(decoding: body, as: UTF8.self)
    }

    func testIncludesLanguageAndPromptFields() {
        let s = bodyString(prompt: "wispr_clone, Shengji")
        XCTAssertTrue(s.contains("name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertTrue(s.contains("name=\"prompt\"\r\n\r\nwispr_clone, Shengji\r\n"))
    }

    func testOmitsPromptFieldWhenEmpty() {
        let s = bodyString(prompt: "")
        XCTAssertFalse(s.contains("name=\"prompt\""))
        XCTAssertTrue(s.contains("name=\"response_format\""))
    }
}
