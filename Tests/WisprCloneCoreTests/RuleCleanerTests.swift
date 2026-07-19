import XCTest
@testable import WisprCloneCore

final class RuleCleanerTests: XCTestCase {
    let cleaner = RuleCleaner()

    func testRemovesFillerWords() async {
        let out = await cleaner.clean("um, so I think, uh, we should ship it")
        XCTAssertEqual(out, "So I think, we should ship it")
    }

    func testRemovesRepeatedFillers() async {
        let out = await cleaner.clean("Umm hmm this works, er, right")
        XCTAssertEqual(out, "This works, right")
    }

    func testCapitalizesAndTrims() async {
        let out = await cleaner.clean("  hello world  ")
        XCTAssertEqual(out, "Hello world")
    }

    func testFixesSpaceBeforePunctuation() async {
        let out = await cleaner.clean("hello , world .")
        XCTAssertEqual(out, "Hello, world.")
    }

    func testChinesePassesThroughUntouched() async {
        let out = await cleaner.clean("请给我一杯水")
        XCTAssertEqual(out, "请给我一杯水")
    }

    func testDoesNotEatWordsContainingFillers() async {
        let out = await cleaner.clean("The drummer performed")
        XCTAssertEqual(out, "The drummer performed")
    }
}
