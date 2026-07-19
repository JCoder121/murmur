# Context Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve dictation accuracy by feeding a personal dictionary into whisper's `initial_prompt` (both modes) and frontmost-app context + tone buckets into qwen's cleanup prompt (Smart mode).

**Architecture:** Two new leaf types — `PersonalDictionary` (loads a user-editable term file, mtime-cached) and `AppContext` (captures frontmost app name + window title at hotkey-press, maps app → tone bucket). `WhisperServer.transcribe` gains a `prompt` multipart field; `OllamaCleaner`'s system prompt becomes a pure function of `AppContext` + dictionary. `AppController` captures context at key-press and threads it through the pipeline.

**Tech Stack:** Swift 5.9 SwiftPM, XCTest, AppKit/ApplicationServices (NSWorkspace + AX), whisper-server multipart API, Ollama chat API.

## Global Constraints

- Interview decisions (2026-07-19): dictionary = plain text file at `~/Library/Application Support/WisprClone/dictionary.txt`; context depth = app name + window title only (NO field-content reads); injection = both whisper `initial_prompt` and qwen prompt; tone = simple built-in app buckets.
- Pure SwiftPM + Makefile — never xcodebuild. Build with `make bundle`, test with `swift test` (needs full Xcode for XCTest).
- All processing stays local; context strings go only to localhost whisper-server/Ollama.
- Whisper `initial_prompt` is token-limited (~224 tokens) — cap the dictionary prompt at 600 chars.
- Existing behavior when dictionary file is missing/empty must be byte-identical to v1 (empty prompt field is fine; whisper-server ignores empty `prompt`).
- After rebuild, relaunch via `pkill -x WisprClone; make run` (open won't restart a running app). Self-signed "WisprClone Dev" cert keeps the Accessibility grant valid.

---

### Task 1: PersonalDictionary

**Files:**
- Create: `Sources/WisprCloneCore/PersonalDictionary.swift`
- Test: `Tests/WisprCloneCoreTests/PersonalDictionaryTests.swift`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces: `PersonalDictionary(fileURL: URL = default)` with `var terms: [String]` and `var initialPrompt: String` (comma-joined terms, ≤600 chars, `""` when no terms). Default file: `~/Library/Application Support/WisprClone/dictionary.txt`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import WisprCloneCore

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PersonalDictionaryTests`
Expected: compile FAIL — `cannot find 'PersonalDictionary' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// User-editable list of proper nouns (one per line, # comments) fed to
/// whisper as initial_prompt and to the smart cleaner as preferred spellings.
public final class PersonalDictionary {
    public static let defaultFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WisprClone/dictionary.txt")

    private let fileURL: URL
    private var cachedTerms: [String] = []
    private var cachedMTime: Date?

    public init(fileURL: URL = PersonalDictionary.defaultFileURL) {
        self.fileURL = fileURL
    }

    public var terms: [String] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
        if mtime != cachedMTime {
            cachedMTime = mtime
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            cachedTerms = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        return cachedTerms
    }

    public var initialPrompt: String {
        var out = ""
        for term in terms {
            let next = out.isEmpty ? term : out + ", " + term
            if next.count > 600 { break }
            out = next
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PersonalDictionaryTests`
Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WisprCloneCore/PersonalDictionary.swift Tests/WisprCloneCoreTests/PersonalDictionaryTests.swift
git commit -m "feat: personal dictionary (file-backed, mtime-cached, capped initial prompt)"
```

### Task 2: AppContext + tone buckets

**Files:**
- Create: `Sources/WisprCloneCore/AppContext.swift`
- Test: `Tests/WisprCloneCoreTests/AppContextTests.swift`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces: `struct AppContext { let appName: String; let windowTitle: String; var bucket: ToneBucket }`, `enum ToneBucket { case chat, code, prose }`, and `@MainActor static func capture() -> AppContext` (AX/NSWorkspace wrapper, untested — logic lives in the pure `bucket(for:)`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import WisprCloneCore

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppContextTests`
Expected: compile FAIL — `cannot find 'AppContext' in scope`

- [ ] **Step 3: Write the implementation**

```swift
import AppKit
import ApplicationServices

public enum ToneBucket { case chat, code, prose }

/// Snapshot of where the user is dictating, captured at hotkey-press
/// (the frontmost app then is the paste target). Never reads field content.
public struct AppContext {
    public let appName: String
    public let windowTitle: String

    public init(appName: String, windowTitle: String) {
        self.appName = appName
        self.windowTitle = windowTitle
    }

    public var bucket: ToneBucket { Self.bucket(for: appName) }

    private static let chatApps: Set<String> =
        ["Slack", "Messages", "Discord", "Telegram", "WhatsApp", "Signal"]
    private static let codeApps: Set<String> =
        ["Terminal", "iTerm2", "Visual Studio Code", "Xcode", "Warp", "Ghostty", "kitty", "Alacritty"]

    static func bucket(for appName: String) -> ToneBucket {
        if chatApps.contains(appName) { return .chat }
        if codeApps.contains(appName) { return .code }
        return .prose
    }

    @MainActor
    public static func capture() -> AppContext {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppContext(appName: "", windowTitle: "")
        }
        let name = app.localizedName ?? ""
        var title = ""
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: AnyObject?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let window = windowRef, CFGetTypeID(window as CFTypeRef) == AXUIElementGetTypeID() {
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success {
                title = (titleRef as? String) ?? ""
            }
        }
        return AppContext(appName: name, windowTitle: title)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppContextTests`
Expected: 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WisprCloneCore/AppContext.swift Tests/WisprCloneCoreTests/AppContextTests.swift
git commit -m "feat: AppContext capture (frontmost app + window title) with tone buckets"
```

### Task 3: whisper initial_prompt plumbing

**Files:**
- Modify: `Sources/WisprCloneCore/WhisperServer.swift` (transcribe, ~line 71; extract body builder)
- Test: `Tests/WisprCloneCoreTests/WhisperBodyTests.swift` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `transcribe(wav: URL, language: Language = .auto, prompt: String = "") async throws -> String`; internal `static func multipartBody(boundary: String, wavData: Data, language: Language, prompt: String) -> Data` (extracted for testability).

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WhisperBodyTests`
Expected: compile FAIL — `type 'WhisperServer' has no member 'multipartBody'`

- [ ] **Step 3: Extract the body builder and add the prompt field**

In `WhisperServer.swift`, replace the body-building section of `transcribe` with a call to the new internal static method:

```swift
    public func transcribe(wav: URL, language: Language = .auto, prompt: String = "") async throws -> String {
        let boundary = "wisprclone-\(UUID().uuidString)"
        var req = URLRequest(url: Self.base.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.multipartBody(
            boundary: boundary, wavData: try Data(contentsOf: wav), language: language, prompt: prompt)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Error.badResponse }
        let text = try WhisperParse.text(from: data)
        return WhisperParse.isNoise(text) ? "" : text
    }

    static func multipartBody(boundary: String, wavData: Data, language: Language, prompt: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n".utf8))
        field("response_format", "json")
        field("language", language.rawValue)  // overrides the server's --language flag
        if !prompt.isEmpty { field("prompt", prompt) }  // whisper initial_prompt: biases decoding toward dictionary terms
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
```

- [ ] **Step 4: Run all tests to verify pass, no regressions**

Run: `swift test`
Expected: all tests PASS (2 new + existing)

- [ ] **Step 5: Commit**

```bash
git add Sources/WisprCloneCore/WhisperServer.swift Tests/WisprCloneCoreTests/WhisperBodyTests.swift
git commit -m "feat: whisper initial_prompt plumbing via extracted multipart builder"
```

### Task 4: Context-aware cleanup prompt

**Files:**
- Modify: `Sources/WisprCloneCore/OllamaCleaner.swift` (systemPrompt ~line 4; `clean` and request builder to accept a prompt string)
- Modify: `Tests/WisprCloneCoreTests/OllamaCleanerTests.swift` (add prompt-composition tests; read the file first — it tests `parse`/payload today)

**Interfaces:**
- Consumes: `AppContext` + `ToneBucket` (Task 2), `PersonalDictionary.terms` (Task 1).
- Produces: `static func systemPrompt(context: AppContext?, dictionaryTerms: [String]) -> String`; `OllamaCleaner.clean(_:)` unchanged signature, but init gains `contextProvider: (() -> (AppContext?, [String]))? = nil` called per-request. Existing `systemPrompt` constant is replaced by the function (base rules string stays as `basePrompt`).

- [ ] **Step 1: Write the failing tests** (append to `OllamaCleanerTests.swift`)

```swift
    func testSystemPromptBaseIncludesSymbolRule() {
        let p = OllamaCleaner.systemPrompt(context: nil, dictionaryTerms: [])
        XCTAssertTrue(p.contains("filler words"))
        XCTAssertTrue(p.contains("spoken symbol names"))
    }

    func testSystemPromptAddsToneLinePerBucket() {
        let chat = OllamaCleaner.systemPrompt(
            context: AppContext(appName: "Slack", windowTitle: "#general"), dictionaryTerms: [])
        XCTAssertTrue(chat.contains("chat app (Slack)"))
        let code = OllamaCleaner.systemPrompt(
            context: AppContext(appName: "Terminal", windowTitle: ""), dictionaryTerms: [])
        XCTAssertTrue(code.contains("terminal or code editor (Terminal)"))
        let prose = OllamaCleaner.systemPrompt(
            context: AppContext(appName: "Notion", windowTitle: "Meeting notes"), dictionaryTerms: [])
        XCTAssertTrue(prose.contains("writing prose in Notion"))
        XCTAssertTrue(prose.contains("Meeting notes"))
    }

    func testSystemPromptListsDictionaryTerms() {
        let p = OllamaCleaner.systemPrompt(context: nil, dictionaryTerms: ["wispr_clone", "Shengji"])
        XCTAssertTrue(p.contains("Preferred spellings: wispr_clone, Shengji"))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OllamaCleanerTests`
Expected: compile FAIL — `systemPrompt` is not a function / missing members

- [ ] **Step 3: Implement prompt composition**

In `OllamaCleaner.swift`, rename the constant and add the composer (keep rules 1–5 verbatim, add rule 6):

```swift
    static let basePrompt = """
    You clean up dictated speech. Rules:
    1. Remove filler words (um, uh, like, you know) and false starts.
    2. Fix punctuation, casing, and obvious grammar slips without changing meaning or tone.
    3. Translate any Chinese into natural English. The output must be entirely English.
    4. If the speech contains a meta-instruction such as "give me the following in English:", \
    apply the instruction to the content that follows instead of writing out the instruction.
    5. Output ONLY the final cleaned text. No quotes, no commentary, no explanations.
    6. Convert spoken symbol names (slash, dash, comma, colon, dot) into characters when \
    context clearly calls for it (e.g. file paths, punctuation); otherwise leave them as words.
    """

    static func systemPrompt(context: AppContext?, dictionaryTerms: [String]) -> String {
        var parts = [basePrompt]
        if let context {
            let title = context.windowTitle.isEmpty ? "" : " (window: \"\(context.windowTitle)\")"
            switch context.bucket {
            case .chat:
                parts.append("The user is typing in a chat app (\(context.appName))\(title); keep it casual and light on punctuation.")
            case .code:
                parts.append("The user is typing in a terminal or code editor (\(context.appName))\(title); preserve technical terms, paths, and symbols exactly.")
            case .prose:
                parts.append("The user is writing prose in \(context.appName.isEmpty ? "an app" : context.appName)\(title); use proper punctuation and capitalization.")
            }
        }
        if !dictionaryTerms.isEmpty {
            parts.append("Preferred spellings: \(dictionaryTerms.joined(separator: ", ")).")
        }
        return parts.joined(separator: "\n")
    }
```

Add the provider to init and use it in the request payload (wherever the old `systemPrompt` constant was referenced):

```swift
    private let contextProvider: (() -> (AppContext?, [String]))?

    // init gains: contextProvider: (() -> (AppContext?, [String]))? = nil
    // payload builder: the "system" message content becomes
    //   Self.systemPrompt(context: ctx, dictionaryTerms: terms)
    // where (ctx, terms) = contextProvider?() ?? (nil, [])
```

Adapt the exact payload-builder code in the file (it currently uses `systemPrompt` directly — read `OllamaCleaner.swift:30-42` and substitute; if the builder is a static func used by tests, thread the composed string in as a parameter).

- [ ] **Step 4: Run all tests to verify pass**

Run: `swift test`
Expected: all PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WisprCloneCore/OllamaCleaner.swift Tests/WisprCloneCoreTests/OllamaCleanerTests.swift
git commit -m "feat: context-aware cleanup prompt (tone buckets, dictionary spellings, symbol rule)"
```

### Task 5: Wiring + docs + manual smoke

**Files:**
- Modify: `Sources/WisprCloneCore/AppController.swift` (`hotkeyPressed` ~line 78, `hotkeyReleased` pipeline ~line 110-122, `makeCleaner` ~line 62)
- Modify: `README.md` (Use + Future ideas sections)

**Interfaces:**
- Consumes: `AppContext.capture()`, `PersonalDictionary` (`terms`, `initialPrompt`), `transcribe(wav:language:prompt:)`, `OllamaCleaner(contextProvider:)`.
- Produces: end-to-end wiring; no new public API.

- [ ] **Step 1: Wire capture and threading in AppController**

Add properties: `private let dictionary = PersonalDictionary()` and `private var dictationContext: AppContext?`.

In `hotkeyPressed()` (first line after the guards): `dictationContext = AppContext.capture()` — capture at press time; the frontmost app then is the paste target.

In `makeCleaner()`, pass the provider to `OllamaCleaner`:

```swift
        case .smart:
            return OllamaCleaner(
                fallback: rules,
                onFallback: { ... existing warning closure ... },
                contextProvider: { [weak self] in
                    (self?.dictationContext, self?.dictionary.terms ?? [])
                })
```

In the `hotkeyReleased` Task, thread the dictionary into whisper:

```swift
                let raw = try await self.whisper.transcribe(
                    wav: wav, language: Settings.language, prompt: self.dictionary.initialPrompt)
```

(`makeCleaner()` is called on the main actor before the Task, as today; `dictationContext` is read inside the provider when qwen builds its request.)

- [ ] **Step 2: Build and run all tests**

Run: `swift test && make bundle`
Expected: all tests PASS, bundle builds

- [ ] **Step 3: Manual smoke (user at machine)**

```bash
mkdir -p "$HOME/Library/Application Support/WisprClone"
printf "wispr_clone\nShengji\nKaladin\nQwen\nOllama\n" > "$HOME/Library/Application Support/WisprClone/dictionary.txt"
pkill -x WisprClone; make run
```

Then verify with the user:
1. Rules mode, English: dictate "I'm working on wispr clone today" → pastes `wispr_clone` (initial_prompt bias).
2. Smart mode in a terminal: dictate "the file is at home slash jeffrey" → `home/jeffrey`.
3. Smart mode in Slack/Messages: dictate a sentence → casual formatting.
4. Empty/missing dictionary file → behavior identical to v1 (no errors).

- [ ] **Step 4: Update README**

In `## Use`, add: dictionary file location, one-term-per-line format, and that it fixes proper-noun spelling in both modes. In `## Future ideas`, remove the "planned next" context-injection bullet (now shipped) and note the tone-bucket map location for extending.

- [ ] **Step 5: Commit**

```bash
git add Sources/WisprCloneCore/AppController.swift README.md
git commit -m "feat: wire context injection end-to-end (dictionary → whisper, app context → qwen)"
```

## Self-Review

- Spec coverage: dictionary file ✓ (T1), app+title capture ✓ (T2), both-layer injection ✓ (T3+T4+T5), tone buckets ✓ (T4), symbol rule from the slash discussion ✓ (T4 rule 6), v1-identical behavior with no dictionary ✓ (T3 empty-prompt omission + T5 smoke item 4).
- Placeholder scan: Task 4 Step 3 asks the implementer to adapt the existing payload builder by reading `OllamaCleaner.swift:30-42` — intentional, since the builder's exact shape is in-repo; the composed-prompt function and its tests are fully specified.
- Type consistency: `Language` (existing), `AppContext`/`ToneBucket` (T2) match usages in T4/T5; `transcribe(wav:language:prompt:)` signature consistent across T3/T5.
