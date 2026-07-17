# wispr_clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar app: hold Right-Cmd → speak EN/ZH → release → clean English text pastes at the cursor, fully offline.

**Architecture:** Pure-Swift SwiftPM executable (library target `WisprCloneCore` + thin `WisprClone` executable) bundled into a `.app` by a Makefile. ASR = `whisper-server` child process (brew whisper-cpp, large-v3-turbo q5_0) spoken to over localhost HTTP; smart cleanup = Ollama (`qwen2.5:3b`) over localhost HTTP with rule-based fallback; insertion = pasteboard + synthesized Cmd-V.

**Tech Stack:** Swift 5.9 manifest (Swift 6.0.3 compiler, Command Line Tools only — NO Xcode), AppKit, AVFoundation, CoreGraphics event taps, XCTest. Zero external SwiftPM dependencies.

## Global Constraints

- Build with `swift build` / `swift test` only — the machine has Command Line Tools, no Xcode.
- No external SwiftPM dependencies. AppKit/AVFoundation/Foundation only.
- Package platform: `.macOS(.v14)`. Tools version `5.9` (keeps Swift-5 language mode; do not enable strict concurrency).
- Whisper model path (verbatim): `~/Library/Application Support/WisprClone/models/ggml-large-v3-turbo-q5_0.bin`
- whisper-server binary search order: `/opt/homebrew/bin/whisper-server`, then `/usr/local/bin/whisper-server`; port `8642`, host `127.0.0.1`, `--language auto`.
- Ollama endpoint `http://127.0.0.1:11434/api/chat`, model `qwen2.5:3b`, request timeout 10s.
- Hotkey: Right Command, keycode `54`, via CGEventTap on `flagsChanged`, listen-only. Holds `< 0.3s` are discarded. Recording hard cap: 2 minutes.
- Whisper idle-unload: terminate whisper-server 600s after last dictation.
- Clipboard: save string contents before insert, restore 0.3s after Cmd-V.
- Disk budget: setup downloads ≈3.2GB total; `scripts/setup.sh` must print sizes and prompt before each download (user has ~18GB free).
- App bundle: `dist/WisprClone.app`, `LSUIElement=true` (menu-bar only), ad-hoc codesign, bundle id `com.jeffrey.wisprclone`.
- Commit after every task (repo: `/Users/jeffrey/Documents/claude_playground/wispr_clone`).

---

### Task 1: Package scaffold + app bundle + menu-bar skeleton

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/WisprClone/main.swift`, `Sources/WisprCloneCore/AppDelegate.swift`, `Resources/Info.plist`, `Makefile`
- Test: manual launch

**Interfaces:**
- Produces: `WisprCloneCore` library target (all later code lives here); `AppDelegate: NSObject, NSApplicationDelegate` with an NSStatusItem and a Quit menu item; `make bundle` / `make run` / `make test`.

- [ ] **Step 1: Write Package.swift and .gitignore**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WisprClone",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WisprCloneCore"),
        .executableTarget(name: "WisprClone", dependencies: ["WisprCloneCore"]),
        .testTarget(name: "WisprCloneCoreTests", dependencies: ["WisprCloneCore"]),
    ]
)
```

`.gitignore`:
```
.build/
dist/
.DS_Store
```

- [ ] **Step 2: Write main.swift and AppDelegate.swift**

`Sources/WisprClone/main.swift`:
```swift
import AppKit
import WisprCloneCore

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/WisprCloneCore/AppDelegate.swift`:
```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎤"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit WisprClone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
```

- [ ] **Step 3: Write Resources/Info.plist and Makefile**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.jeffrey.wisprclone</string>
    <key>CFBundleName</key><string>WisprClone</string>
    <key>CFBundleExecutable</key><string>WisprClone</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>WisprClone records your voice while you hold the dictation hotkey.</string>
</dict>
</plist>
```

`Makefile`:
```make
APP = WisprClone
BIN = .build/release/$(APP)
BUNDLE = dist/$(APP).app

.PHONY: build bundle run test clean

build:
	swift build -c release

bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP)
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	codesign --force -s - --identifier com.jeffrey.wisprclone $(BUNDLE)

run: bundle
	open $(BUNDLE)

test:
	swift test

clean:
	rm -rf .build dist
```

- [ ] **Step 4: Build and launch**

Run: `make run`
Expected: 🎤 appears in the menu bar; dropdown shows "Quit WisprClone"; no Dock icon. Quit works.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SwiftPM scaffold, app bundle Makefile, menu-bar skeleton"
```

---

### Task 2: HotkeyMonitor (Right-Cmd hold via CGEventTap) — riskiest piece, done early

**Files:**
- Create: `Sources/WisprCloneCore/HotkeyMonitor.swift`
- Modify: `Sources/WisprCloneCore/AppDelegate.swift`
- Test: manual (system event taps aren't unit-testable)

**Interfaces:**
- Produces: `final class HotkeyMonitor` with `var onPress: (() -> Void)?`, `var onRelease: ((TimeInterval) -> Void)?` (arg = held seconds), `func start() -> Bool` (false = no Accessibility permission).

- [ ] **Step 1: Write HotkeyMonitor.swift**

```swift
import AppKit
import CoreGraphics

public final class HotkeyMonitor {
    public var onPress: (() -> Void)?
    public var onRelease: ((TimeInterval) -> Void)?

    private var tap: CFMachPort?
    private var pressedAt: Date?
    private static let rightCmdKeycode: Int64 = 54

    public init() {}

    /// Returns false if the event tap could not be created (usually: Accessibility not granted).
    public func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS disables taps it thinks are slow; always re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.rightCmdKeycode else { return }
        let isDown = event.flags.contains(.maskCommand)
        if isDown, pressedAt == nil {
            pressedAt = Date()
            onPress?()
        } else if !isDown, let start = pressedAt {
            pressedAt = nil
            onRelease?(Date().timeIntervalSince(start))
        }
    }
}
```

- [ ] **Step 2: Wire a temporary smoke test into AppDelegate**

Add to `AppDelegate` (fields + end of `applicationDidFinishLaunching`):
```swift
    private let hotkey = HotkeyMonitor()
```
```swift
        if !AXIsProcessTrusted() {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        hotkey.onPress = { [weak self] in self?.statusItem.button?.title = "🔴" }
        hotkey.onRelease = { [weak self] held in
            self?.statusItem.button?.title = "🎤"
            NSLog("hotkey held %.2fs", held)
        }
        if !hotkey.start() {
            NSLog("HotkeyMonitor: event tap failed — grant Accessibility and relaunch")
        }
```
(`statusItem` must become `private var statusItem: NSStatusItem!` — it already is.)

- [ ] **Step 3: Manual verification**

Run: `make run` → grant Accessibility for WisprClone in System Settings when prompted → relaunch (`make run`).
Expected: menu-bar icon flips 🎤→🔴 while Right-Cmd is held, anywhere in the OS, and back on release; held duration logged (`log stream --predicate 'process == "WisprClone"'` or Console.app). Left-Cmd does nothing. Cmd+C etc. still work normally in other apps.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: Right-Cmd hold detection via CGEventTap"
```

---

### Task 3: RuleCleaner + Cleaner protocol (TDD)

**Files:**
- Create: `Sources/WisprCloneCore/Cleaner.swift`, `Sources/WisprCloneCore/RuleCleaner.swift`
- Test: `Tests/WisprCloneCoreTests/RuleCleanerTests.swift`

**Interfaces:**
- Produces: `protocol Cleaner { func clean(_ transcript: String) async -> String }`; `struct RuleCleaner: Cleaner` with `init()`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```
- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RuleCleanerTests`
Expected: FAIL to compile — `Cleaner`/`RuleCleaner` not defined.

- [ ] **Step 3: Implement**

`Sources/WisprCloneCore/Cleaner.swift`:
```swift
public protocol Cleaner {
    func clean(_ transcript: String) async -> String
}
```

`Sources/WisprCloneCore/RuleCleaner.swift`:
```swift
import Foundation

public struct RuleCleaner: Cleaner {
    public init() {}

    public func clean(_ transcript: String) async -> String {
        var s = transcript
        // Standalone fillers, optionally followed by a comma/period.
        s = s.replacingOccurrences(
            of: #"(?i)(?<![\p{L}])(um+|uh+|uhm+|er+m?|ah|hm+m?|mm+)(?![\p{L}])[,.]?\s*"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a leading orphaned comma left by a removed filler ("um, so" -> ", so").
        s = s.replacingOccurrences(of: #"^[,.;:]\s*"#, with: "", options: .regularExpression)
        if let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RuleCleanerTests`
Expected: PASS (6 tests). If a specific assertion fails, adjust the regex, not the test.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Cleaner protocol and rule-based filler cleanup"
```

---

### Task 4: WAVWriter (TDD)

**Files:**
- Create: `Sources/WisprCloneCore/WAVWriter.swift`
- Test: `Tests/WisprCloneCoreTests/WAVWriterTests.swift`

**Interfaces:**
- Produces: `enum WAVWriter { static func write(samples: [Float], sampleRate: Int, to url: URL) throws }` — 16-bit mono PCM WAV.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import WisprCloneCore

final class WAVWriterTests: XCTestCase {
    func testWritesValidMono16kHeader() throws {
        let samples = [Float](repeating: 0.5, count: 16000) // 1s
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavwriter-test.wav")
        try WAVWriter.write(samples: samples, sampleRate: 16000, to: url)
        let data = try Data(contentsOf: url)

        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        // fmt chunk: PCM(1), mono(1), 16000 Hz, 16-bit
        XCTAssertEqual(data[20], 1); XCTAssertEqual(data[22], 1)
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(rate, 16000)
        XCTAssertEqual(data[34], 16)
        // data chunk size = 16000 samples * 2 bytes
        let dataSize = data[40..<44].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(dataSize, 32000)
        XCTAssertEqual(data.count, 44 + 32000)
    }

    func testClampsOutOfRangeSamples() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wavwriter-clamp.wav")
        try WAVWriter.write(samples: [2.0, -2.0], sampleRate: 16000, to: url)
        let data = try Data(contentsOf: url)
        let s0 = data[44..<46].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        let s1 = data[46..<48].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        XCTAssertEqual(s0, Int16.max)
        XCTAssertEqual(s1, Int16.min)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WAVWriterTests`
Expected: FAIL to compile — `WAVWriter` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum WAVWriter {
    public static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        let dataSize = samples.count * 2
        var d = Data(capacity: 44 + dataSize)

        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1)                          // PCM
        u16(1)                          // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))     // byte rate
        u16(2)                          // block align
        u16(16)                         // bits per sample
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataSize))

        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let i = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: i.littleEndian) { d.append(contentsOf: $0) }
        }
        try d.write(to: url)
    }
}
```
Note: `Int16(-1.0 * 32767) = -32767`, but the clamp test expects `Int16.min` (-32768) for -2.0. Handle it: replace the loop body's conversion with
```swift
            let i: Int16 = clamped <= -1.0 ? .min : Int16(clamped * Float(Int16.max))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WAVWriterTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: 16-bit mono WAV writer"
```

---

### Task 5: Recorder (AVAudioEngine → 16kHz mono WAV)

**Files:**
- Create: `Sources/WisprCloneCore/Recorder.swift`
- Test: manual (mic hardware)

**Interfaces:**
- Consumes: `WAVWriter.write(samples:sampleRate:to:)`
- Produces: `final class Recorder` with `var levelHandler: ((Float) -> Void)?` (RMS 0–1, called on audio thread), `func start() throws`, `func stop() throws -> URL?` (nil if under ~0.5s of audio; WAV in temp dir otherwise), and `static func requestMicPermission()`.

- [ ] **Step 1: Implement Recorder.swift**

```swift
import AVFoundation

public final class Recorder {
    public var levelHandler: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private static let maxSamples = 16000 * 120  // 2 min cap

    public init() {}

    public static func requestMicPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { NSLog("Recorder: microphone permission denied") }
        }
    }

    public func start() throws {
        lock.lock(); samples = []; lock.unlock()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "Recorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "audio format setup failed"])
        }
        self.converter = converter
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer, converter: converter, outFormat: outFormat)
        }
        engine.prepare()
        try engine.start()
    }

    private func consume(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter, outFormat: AVAudioFormat) {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var consumed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, let ch = out.floatChannelData else { return }
        let n = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: ch[0], count: n))

        lock.lock()
        if samples.count < Self.maxSamples { samples.append(contentsOf: chunk) }
        lock.unlock()

        if n > 0 {
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(n))
            levelHandler?(min(1, rms * 8))
        }
    }

    public func stop() throws -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        lock.lock(); let captured = samples; samples = []; lock.unlock()
        guard captured.count > 8000 else { return nil }  // < 0.5s: discard
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wispr-\(UUID().uuidString).wav")
        try WAVWriter.write(samples: captured, sampleRate: 16000, to: url)
        return url
    }
}
```

- [ ] **Step 2: Wire a temporary smoke test into AppDelegate**

In `applicationDidFinishLaunching`, add `Recorder.requestMicPermission()` and replace the Task-2 hotkey handlers with:
```swift
        let recorder = Recorder()
        self.recorder = recorder  // add field: private var recorder: Recorder?
        hotkey.onPress = { [weak self] in
            self?.statusItem.button?.title = "🔴"
            try? recorder.start()
        }
        hotkey.onRelease = { [weak self] held in
            self?.statusItem.button?.title = "🎤"
            let url = try? recorder.stop()
            NSLog("held %.2fs, wav: %@", held, url??.path ?? "nil")
        }
```

- [ ] **Step 3: Manual verification**

Run: `make run` → grant mic permission → hold Right-Cmd, say "testing one two three", release.
Expected: log line with a `/var/folders/.../wispr-….wav` path. Then: `afplay <that path>` plays your voice clearly. A <0.5s tap logs `wav: nil`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: mic capture to 16kHz mono WAV via AVAudioEngine"
```

---

### Task 6: WhisperServer (process lifecycle + /inference client)

**Files:**
- Create: `Sources/WisprCloneCore/WhisperServer.swift`, `Sources/WisprCloneCore/WhisperParse.swift`
- Test: `Tests/WisprCloneCoreTests/WhisperParseTests.swift` (pure parsing), manual for lifecycle

**Interfaces:**
- Produces: `final class WhisperServer` with `init()`, `func ensureRunning() async throws`, `func transcribe(wav: URL) async throws -> String` (returns "" for silence/noise), `func stop()`, `var isModelInstalled: Bool`. Also `enum WhisperParse { static func text(from: Data) throws -> String; static func isNoise(_ s: String) -> Bool }`.

- [ ] **Step 1: Write the failing parse tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter WhisperParseTests`
Expected: FAIL to compile — `WhisperParse` not defined.

- [ ] **Step 3: Implement WhisperParse.swift**

```swift
import Foundation

public enum WhisperParse {
    public static func text(from data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        return try JSONDecoder().decode(Response.self, from: data)
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper emits bracketed pseudo-events for non-speech: [BLANK_AUDIO], (music)...
    public static func isNoise(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return t.range(of: #"^[\[(][^\])]*[\])]$"#, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter WhisperParseTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Implement WhisperServer.swift**

```swift
import Foundation

public final class WhisperServer {
    public static let modelPath = ("~/Library/Application Support/WisprClone/models/ggml-large-v3-turbo-q5_0.bin" as NSString).expandingTildeInPath
    private static let binaryCandidates = ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
    private static let base = URL(string: "http://127.0.0.1:8642")!

    private var process: Process?

    public init() {}

    public var isModelInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.modelPath)
    }

    public enum Error: Swift.Error, LocalizedError {
        case binaryMissing, modelMissing, startTimeout, badResponse
        public var errorDescription: String? {
            switch self {
            case .binaryMissing: "whisper-server not found — run scripts/setup.sh"
            case .modelMissing: "whisper model not found — run scripts/setup.sh"
            case .startTimeout: "whisper-server did not become ready"
            case .badResponse: "whisper-server returned an unexpected response"
            }
        }
    }

    public func ensureRunning() async throws {
        if process?.isRunning == true, await healthy() { return }
        guard let bin = Self.binaryCandidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { throw Error.binaryMissing }
        guard isModelInstalled else { throw Error.modelMissing }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["-m", Self.modelPath, "--host", "127.0.0.1", "--port", "8642", "--language", "auto"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        process = p

        for _ in 0..<60 {  // up to 30s for first model load
            try await Task.sleep(nanoseconds: 500_000_000)
            if await healthy() { return }
            if !p.isRunning { break }
        }
        stop()
        throw Error.startTimeout
    }

    private func healthy() async -> Bool {
        var req = URLRequest(url: Self.base); req.timeoutInterval = 1
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    public func transcribe(wav: URL) async throws -> String {
        let boundary = "wisprclone-\(UUID().uuidString)"
        var req = URLRequest(url: Self.base.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: wav))
        body.append(Data("\r\n".utf8))
        field("response_format", "json")
        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Error.badResponse }
        let text = try WhisperParse.text(from: data)
        return WhisperParse.isNoise(text) ? "" : text
    }

    public func stop() {
        process?.terminate()
        process = nil
    }
}
```

- [ ] **Step 6: Manual verification (requires setup — OK to defer until after Task 10 if whisper-cpp/model not yet installed)**

```bash
brew install whisper-cpp   # ~15MB, if not present
mkdir -p ~/Library/Application\ Support/WisprClone/models
curl -L -o ~/Library/Application\ Support/WisprClone/models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin   # ~574MB
```
Then temporarily in AppDelegate's `onRelease`, after getting the wav URL:
```swift
            guard let wav = url ?? nil else { return }
            Task {
                let server = WhisperServer()
                try await server.ensureRunning()
                let text = try await server.transcribe(wav: wav)
                NSLog("transcript: %@", text)
            }
```
Run `make run`, dictate "hello this is a test", expect `transcript: Hello, this is a test.` in the log. Also dictate a Mandarin sentence and confirm Chinese characters come back.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: whisper-server lifecycle management and inference client"
```

---

### Task 7: OllamaCleaner (smart mode, TDD for request/response + fallback)

**Files:**
- Create: `Sources/WisprCloneCore/OllamaCleaner.swift`
- Test: `Tests/WisprCloneCoreTests/OllamaCleanerTests.swift`

**Interfaces:**
- Consumes: `Cleaner`, `RuleCleaner`
- Produces: `final class OllamaCleaner: Cleaner` with `init(endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!, model: String = "qwen2.5:3b", timeout: TimeInterval = 10, fallback: Cleaner, onFallback: (() -> Void)? = nil)`; static pure helpers `buildBody(model:transcript:) -> Data` and `parse(_ data: Data) throws -> String`.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter OllamaCleanerTests`
Expected: FAIL to compile — `OllamaCleaner` not defined.

- [ ] **Step 3: Implement**

```swift
import Foundation

public final class OllamaCleaner: Cleaner {
    static let systemPrompt = """
    You clean up dictated speech. Rules:
    1. Remove filler words (um, uh, like, you know) and false starts.
    2. Fix punctuation, casing, and obvious grammar slips without changing meaning or tone.
    3. Translate any Chinese into natural English. The output must be entirely English.
    4. If the speech contains a meta-instruction such as "give me the following in English:", \
    apply the instruction to the content that follows instead of writing out the instruction.
    5. Output ONLY the final cleaned text. No quotes, no commentary, no explanations.
    """

    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval
    private let fallback: Cleaner
    private let onFallback: (() -> Void)?

    public init(endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
                model: String = "qwen2.5:3b",
                timeout: TimeInterval = 10,
                fallback: Cleaner,
                onFallback: (() -> Void)? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
        self.fallback = fallback
        self.onFallback = onFallback
    }

    static func buildBody(model: String, transcript: String) -> Data {
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func parse(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        return try JSONDecoder().decode(Response.self, from: data)
            .message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func clean(_ transcript: String) async -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.buildBody(model: model, transcript: transcript)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let out = try Self.parse(data)
            guard !out.isEmpty else { throw URLError(.zeroByteResource) }
            return out
        } catch {
            onFallback?()
            return await fallback.clean(transcript)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter OllamaCleanerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Ollama smart cleaner with rule-based fallback"
```

---

### Task 8: Inserter (pasteboard + Cmd-V with clipboard restore)

**Files:**
- Create: `Sources/WisprCloneCore/Inserter.swift`
- Test: manual (posting keyboard events)

**Interfaces:**
- Produces: `enum Inserter { static func insert(_ text: String) }` — must be called on the main thread.

- [ ] **Step 1: Implement Inserter.swift**

```swift
import AppKit
import CoreGraphics

public enum Inserter {
    /// Pastes `text` into the focused app. Saves and restores the previous
    /// string clipboard contents (v1 limitation: non-string clipboard data,
    /// e.g. images, is not restored).
    public static func insert(_ text: String) {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeycode: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeycode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let saved { pb.setString(saved, forType: .string) }
        }
    }
}
```

- [ ] **Step 2: Manual verification**

Temporarily add to AppDelegate's `onRelease` (replacing prior smoke code):
```swift
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                Inserter.insert("hello from wispr 你好→works")
            }
```
Run `make run`, copy some other text (e.g. "SAVED") first, click into TextEdit, tap Right-Cmd.
Expected: `hello from wispr 你好→works` appears at the cursor (CJK + arrow intact); after ~1s, Cmd-V elsewhere pastes "SAVED" again (clipboard restored).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: paste-at-cursor insertion with clipboard save/restore"
```

---

### Task 9: Overlay pill (recording / processing / warning states)

**Files:**
- Create: `Sources/WisprCloneCore/Overlay.swift`
- Test: manual

**Interfaces:**
- Produces: `@MainActor final class Overlay` with `func showRecording()`, `func updateLevel(_ level: Float)`, `func showProcessing()`, `func showWarning(_ message: String)` (auto-hides after 2s), `func hide()`.

- [ ] **Step 1: Implement Overlay.swift**

```swift
import AppKit

@MainActor
public final class Overlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView(frame: NSRect(x: 0, y: 0, width: 14, height: 14))

    public init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        content.layer?.cornerRadius = 20

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 7
        dot.setFrameOrigin(NSPoint(x: 16, y: 13))

        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 40, y: 11, width: 170, height: 18)

        content.addSubview(dot)
        content.addSubview(label)
        panel.contentView = content
    }

    private func show(text: String, dotColor: NSColor?) {
        label.stringValue = text
        dot.isHidden = dotColor == nil
        if let dotColor { dot.layer?.backgroundColor = dotColor.cgColor }
        if let screen = NSScreen.main {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - f.width / 2,
                y: screen.visibleFrame.minY + 60))
        }
        panel.orderFrontRegardless()
    }

    public func showRecording() { show(text: "Listening…", dotColor: .systemRed) }
    public func showProcessing() { show(text: "Processing…", dotColor: .systemYellow) }

    public func updateLevel(_ level: Float) {
        let scale = 1.0 + CGFloat(min(1, max(0, level)))
        dot.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
    }

    public func showWarning(_ message: String) {
        show(text: message, dotColor: .systemOrange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.hide() }
    }

    public func hide() { panel.orderOut(nil) }
}
```

- [ ] **Step 2: Manual verification**

Temporarily wire in AppDelegate: `onPress` → `overlay.showRecording()`, `onRelease` → `overlay.showProcessing()` then `overlay.hide()` after 1s.
Run `make run`. Expected: dark pill appears bottom-center over any app (incl. full-screen), red dot while holding, yellow "Processing…" for 1s after release, then gone. It never steals focus (cursor stays where you were typing).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "feat: floating status pill overlay"
```

---

### Task 10: Settings + AppController (full pipeline wiring, mode toggle, idle unload)

**Files:**
- Create: `Sources/WisprCloneCore/Settings.swift`, `Sources/WisprCloneCore/AppController.swift`
- Modify: `Sources/WisprCloneCore/AppDelegate.swift` (strip all smoke-test code; delegate everything to AppController)
- Test: `Tests/WisprCloneCoreTests/SettingsTests.swift` + manual end-to-end

**Interfaces:**
- Consumes: everything from Tasks 2–9 (exact signatures as specified in each task's Produces block)
- Produces: `enum Mode: String { case smart, rules }`; `enum Settings { static var mode: Mode }` (UserDefaults-backed, key `"mode"`, default `.smart`); `@MainActor final class AppController` with `init()` and `func start()`.

- [ ] **Step 1: Write the failing Settings test**

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsTests`
Expected: FAIL to compile — `Settings` not defined.

- [ ] **Step 3: Implement Settings.swift**

```swift
import Foundation

public enum Mode: String {
    case smart, rules
}

public enum Settings {
    public static var mode: Mode {
        get { UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .smart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Implement AppController.swift**

```swift
import AppKit

@MainActor
public final class AppController: NSObject {
    private let hotkey = HotkeyMonitor()
    private let recorder = Recorder()
    private let whisper = WhisperServer()
    private let overlay = Overlay()
    private var statusItem: NSStatusItem!
    private var smartItem: NSMenuItem!
    private var rulesItem: NSMenuItem!
    private var idleTimer: Timer?
    private var recording = false

    public func start() {
        buildMenu()
        Recorder.requestMicPermission()
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }

        recorder.levelHandler = { [weak self] level in
            DispatchQueue.main.async { self?.overlay.updateLevel(level) }
        }
        hotkey.onPress = { [weak self] in self?.hotkeyPressed() }
        hotkey.onRelease = { [weak self] held in self?.hotkeyReleased(held: held) }
        if !hotkey.start() {
            overlay.showWarning("Grant Accessibility, then relaunch")
        }
        if !whisper.isModelInstalled {
            overlay.showWarning("Model missing — run scripts/setup.sh")
        }
    }

    // MARK: menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎤"
        let menu = NSMenu()
        smartItem = NSMenuItem(title: "Smart mode (LLM + translate)", action: #selector(pickSmart), keyEquivalent: "")
        rulesItem = NSMenuItem(title: "Rules mode (instant, EN only)", action: #selector(pickRules), keyEquivalent: "")
        smartItem.target = self
        rulesItem.target = self
        menu.addItem(smartItem)
        menu.addItem(rulesItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WisprClone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshChecks()
    }

    @objc private func pickSmart() { Settings.mode = .smart; refreshChecks() }
    @objc private func pickRules() { Settings.mode = .rules; refreshChecks() }

    private func refreshChecks() {
        smartItem.state = Settings.mode == .smart ? .on : .off
        rulesItem.state = Settings.mode == .rules ? .on : .off
    }

    private func makeCleaner() -> Cleaner {
        let rules = RuleCleaner()
        switch Settings.mode {
        case .rules:
            return rules
        case .smart:
            return OllamaCleaner(fallback: rules, onFallback: {
                DispatchQueue.main.async { [weak self] in
                    self?.overlay.showWarning("Ollama down — used rules mode")
                }
            })
        }
    }

    // MARK: dictation pipeline

    private func hotkeyPressed() {
        guard !recording else { return }
        recording = true
        idleTimer?.invalidate()
        statusItem.button?.title = "🔴"
        overlay.showRecording()
        Task { try? await whisper.ensureRunning() }  // warm up while user speaks
        do { try recorder.start() } catch {
            recording = false
            overlay.showWarning("Microphone error")
        }
    }

    private func hotkeyReleased(held: TimeInterval) {
        guard recording else { return }
        recording = false
        statusItem.button?.title = "🎤"
        // stop() is `throws -> URL?`, so `try?` yields URL?? — flatten with `?? nil`.
        let wav = (try? recorder.stop()) ?? nil
        guard held >= 0.3, let wav else {
            overlay.hide()
            return
        }
        overlay.showProcessing()
        let cleaner = makeCleaner()
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.scheduleIdleUnload() } }
            do {
                try await self.whisper.ensureRunning()
                let raw = try await self.whisper.transcribe(wav: wav)
                try? FileManager.default.removeItem(at: wav)
                guard !raw.isEmpty else {
                    await MainActor.run { self.overlay.hide() }
                    return
                }
                let cleaned = await cleaner.clean(raw)
                await MainActor.run {
                    Inserter.insert(cleaned)
                    self.overlay.hide()
                }
            } catch {
                try? FileManager.default.removeItem(at: wav)
                await MainActor.run {
                    self.overlay.showWarning(error.localizedDescription)
                }
            }
        }
    }

    private func scheduleIdleUnload() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.whisper.stop() }
        }
    }
}
```

- [ ] **Step 6: Rewrite AppDelegate.swift to delegate**

```swift
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
        controller.start()
    }
}
```

- [ ] **Step 7: Full test suite + build**

Run: `swift test && make bundle`
Expected: all tests PASS; bundle builds cleanly.

- [ ] **Step 8: Manual pipeline check (rules mode; Ollama not required)**

Run: `make run` → menu: pick "Rules mode" → click into TextEdit → hold Right-Cmd, say "um, hello world, this is, uh, a test", release.
Expected: pill shows Listening→Processing; ~1–3s later `Hello world, this is, a test.`-style text appears at the cursor.

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "feat: full dictation pipeline with mode toggle and idle unload"
```

---

### Task 11: setup.sh + README

**Files:**
- Create: `scripts/setup.sh`, `README.md`

**Interfaces:**
- Consumes: paths/ports from Global Constraints (must match `WhisperServer.modelPath` and Ollama model name exactly).

- [ ] **Step 1: Write scripts/setup.sh**

```bash
#!/bin/bash
# wispr_clone setup: installs whisper-cpp + model, optionally Ollama + qwen2.5:3b.
# Prints disk cost and asks before every download (machine has limited free space).
set -euo pipefail

MODEL_DIR="$HOME/Library/Application Support/WisprClone/models"
MODEL_FILE="$MODEL_DIR/ggml-large-v3-turbo-q5_0.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"

confirm() { read -r -p "$1 [y/N] " a; [[ "$a" == "y" || "$a" == "Y" ]]; }

echo "== wispr_clone setup =="
df -h / | awk 'NR==2 {print "Free disk: " $4}'

if ! command -v brew >/dev/null; then
  echo "ERROR: Homebrew required (https://brew.sh)"; exit 1
fi

# 1. whisper-cpp (~15MB)
if command -v whisper-server >/dev/null; then
  echo "✓ whisper-server already installed"
else
  confirm "Install whisper-cpp via brew (~15MB)?" && brew install whisper-cpp
fi

# 2. Whisper model (~574MB)
if [[ -f "$MODEL_FILE" ]]; then
  echo "✓ whisper model already present"
else
  if confirm "Download whisper large-v3-turbo q5_0 model (~574MB)?"; then
    mkdir -p "$MODEL_DIR"
    curl -L --progress-bar -o "$MODEL_FILE" "$MODEL_URL"
  fi
fi

# 3. Ollama + qwen2.5:3b (optional — needed only for Smart mode)
echo ""
echo "Smart mode (LLM cleanup + Chinese→English) needs Ollama + qwen2.5:3b (~2.5GB total)."
echo "Rules mode works without it."
if ! command -v ollama >/dev/null; then
  confirm "Install Ollama via brew (~0.5GB)?" && brew install ollama
fi
if command -v ollama >/dev/null; then
  if ollama list 2>/dev/null | grep -q "qwen2.5:3b"; then
    echo "✓ qwen2.5:3b already pulled"
  else
    if confirm "Pull qwen2.5:3b model (~1.9GB)?"; then
      # ollama serve must be running; try to start it if not.
      pgrep -x ollama >/dev/null || (ollama serve >/dev/null 2>&1 &) 
      sleep 2
      ollama pull qwen2.5:3b
    fi
  fi
fi

echo ""
echo "Done. Build & run the app with: make run"
echo "Grant Accessibility + Microphone permissions when prompted, then hold Right-Cmd and speak."
```

- [ ] **Step 2: Make executable, run it**

Run: `chmod +x scripts/setup.sh && ./scripts/setup.sh`
Expected: prints free disk; installs/downloads with confirmation prompts; idempotent (second run prints ✓ lines). After it completes, whisper-server + model exist; if Ollama chosen, `ollama list` shows qwen2.5:3b.

- [ ] **Step 3: Write README.md**

```markdown
# wispr_clone

Local, offline smart dictation for macOS. Hold **Right-Cmd**, speak English /
Mandarin / a mix, release — clean **English text** is pasted at your cursor.

Built for a MacBook Air M1 (8GB): whisper large-v3-turbo (quantized, Metal)
for speech recognition, Qwen2.5-3B via Ollama for cleanup + Chinese→English
translation, with an instant rules-only fallback mode.

## Setup

```bash
./scripts/setup.sh   # installs whisper-cpp (~15MB), whisper model (~574MB),
                     # optionally Ollama + qwen2.5:3b (~2.5GB, Smart mode only)
make run             # builds dist/WisprClone.app and opens it
```

On first run grant **Microphone** and **Accessibility** permissions
(System Settings → Privacy & Security), then relaunch.

## Use

- Hold **Right-Cmd** → speak → release. Text appears at your cursor.
- Menu-bar 🎤 → switch **Smart mode** (LLM cleanup, zh→en translation) vs
  **Rules mode** (instant, filler-stripping only, no translation).
- Smart mode falls back to rules automatically if Ollama isn't running
  (start it with `ollama serve`).
- Say "give me the following in English: {Chinese}" to dictate Chinese and
  insert the English translation.

## Notes

- Whisper model loads on first dictation (~2s) and unloads after 10 min idle.
- Insertion uses clipboard + Cmd-V; your previous clipboard **string** is
  restored ~0.3s later (images/rich content are not restored).
- Recording caps at 2 minutes per dictation. Holds under 0.3s are ignored.
- Rebuilding the app (ad-hoc signature) may occasionally require re-granting
  Accessibility permission.

## Dev

```bash
swift test    # unit tests
make bundle   # build dist/WisprClone.app without launching
```
```

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: setup script and README"
```

---

### Task 12: End-to-end acceptance checklist (manual)

**Files:** none (verification only)

**Interfaces:** consumes the finished app.

- [ ] **Step 1: Rules mode flows** (menu → Rules mode)
1. TextEdit: "um, hello world, this is, uh, a test" → fillers gone, capitalized, pasted at cursor.
2. Chrome address bar: dictate a search phrase → lands in the focused field.
3. Tap Right-Cmd for <0.3s → nothing pasted, overlay disappears.
4. Hold Right-Cmd in silence for 2s → nothing pasted (noise/silence discarded).

- [ ] **Step 2: Smart mode flows** (menu → Smart mode; `ollama serve` running)
5. "so um I think we should uh probably ship this tomorrow" → clean English, fillers and false starts gone.
6. "give me the following in English: 我明天要去北京开会" → English translation only (e.g. "I'm going to Beijing tomorrow for a meeting"), no Chinese characters, instruction not echoed.
7. Speak a pure-Mandarin sentence → English translation inserted.

- [ ] **Step 3: Failure modes**
8. Kill Ollama (`pkill ollama`), Smart mode → dictation still works via rules; "Ollama down" warning pill shows.
9. Clipboard: copy "KEEP", dictate something, wait 1s, Cmd-V → "KEEP" pastes (restored).
10. Wait 10+ min, `pgrep whisper-server` → empty (idle unload). Dictate again → works (relaunches, ~2s first-word delay).

- [ ] **Step 4: Record results**

Append a `## v1 acceptance` section to README listing date + pass/fail per item; fix or file follow-ups for any failure.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "docs: v1 acceptance results"
```
