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
