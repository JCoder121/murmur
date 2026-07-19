import XCTest
@testable import ChirpCore

final class PersonalDictionaryTests: XCTestCase {
    private func tempFile(_ contents: String?) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dict-\(UUID().uuidString).txt")
        if let contents { try contents.write(to: url, atomically: true, encoding: .utf8) }
        return url
    }

    func testMissingFileYieldsEmpty() throws {
        let dict = PersonalDictionary(fileURL: try tempFile(nil))
        XCTAssertEqual(dict.terms, [])
        XCTAssertEqual(dict.initialPrompt, "")
    }

    func testLoadsTermsSkippingBlanksAndComments() throws {
        let dict = PersonalDictionary(fileURL: try tempFile("""
        wispr_clone

        # projects
        Shengji
          Kaladin
        """))
        XCTAssertEqual(dict.terms, ["wispr_clone", "Shengji", "Kaladin"])
        XCTAssertEqual(dict.initialPrompt, "wispr_clone, Shengji, Kaladin")
    }

    func testInitialPromptCappedAt600Chars() throws {
        let terms = (0..<100).map { "verylongprojectname\($0)" }
        let dict = PersonalDictionary(fileURL: try tempFile(terms.joined(separator: "\n")))
        XCTAssertLessThanOrEqual(dict.initialPrompt.count, 600)
        XCTAssertTrue(dict.initialPrompt.hasPrefix("verylongprojectname0"))
    }

    func testReloadsWhenFileChanges() throws {
        let url = try tempFile("first")
        let dict = PersonalDictionary(fileURL: url)
        XCTAssertEqual(dict.terms, ["first"])
        // Backdate-proof: write new content with a distinct mtime.
        try "second".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: url.path)
        XCTAssertEqual(dict.terms, ["second"])
    }
}
