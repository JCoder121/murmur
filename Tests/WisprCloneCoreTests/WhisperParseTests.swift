import XCTest
@testable import WisprCloneCore

final class WhisperParseTests: XCTestCase {
    func testParsesTextField() throws {
        let data = #"{"text": "  Hello world.\n"}"#.data(using: .utf8)!
        XCTAssertEqual(try WhisperParse.text(from: data), "Hello world.")
    }

    func testThrowsOnMalformedJSON() {
        XCTAssertThrowsError(try WhisperParse.text(from: Data("nope".utf8)))
    }

    func testNoiseDetection() {
        XCTAssertTrue(WhisperParse.isNoise(""))
        XCTAssertTrue(WhisperParse.isNoise("[BLANK_AUDIO]"))
        XCTAssertTrue(WhisperParse.isNoise("(wind blowing)"))
        XCTAssertTrue(WhisperParse.isNoise("[Music]"))
        XCTAssertFalse(WhisperParse.isNoise("Hello there"))
    }
}
