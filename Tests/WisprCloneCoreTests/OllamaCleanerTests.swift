import XCTest
@testable import WisprCloneCore

final class OllamaCleanerTests: XCTestCase {
    func testBuildBodyContainsModelPromptAndTranscript() throws {
        let body = OllamaCleaner.buildBody(model: "qwen2.5:3b", transcript: "um hello 你好")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "qwen2.5:3b")
        XCTAssertEqual(json["stream"] as? Bool, false)
        let messages = json["messages"] as! [[String: String]]
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[0]["content"]!.contains("Translate any Chinese"))
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "um hello 你好")
    }

    func testParsesMessageContent() throws {
        let data = #"{"message": {"role": "assistant", "content": " Hello. \n"}}"#.data(using: .utf8)!
        XCTAssertEqual(try OllamaCleaner.parse(data), "Hello.")
    }

    func testFallsBackWhenServerUnreachable() async {
        final class SpyCleaner: Cleaner {
            var called = false
            func clean(_ t: String) async -> String { called = true; return "FALLBACK:" + t }
        }
        let spy = SpyCleaner()
        var warned = false
        // Port 1 — nothing listens there; connection fails fast.
        let cleaner = OllamaCleaner(
            endpoint: URL(string: "http://127.0.0.1:1/api/chat")!,
            timeout: 2, fallback: spy, onFallback: { warned = true })
        let out = await cleaner.clean("um hello")
        XCTAssertEqual(out, "FALLBACK:um hello")
        XCTAssertTrue(spy.called)
        XCTAssertTrue(warned)
    }
}
