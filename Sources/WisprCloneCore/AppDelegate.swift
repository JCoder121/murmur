import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotkey = HotkeyMonitor()
    private var recorder: Recorder?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎤"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit WisprClone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        if !AXIsProcessTrusted() {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        Recorder.requestMicPermission()
        let recorder = Recorder()
        self.recorder = recorder
        hotkey.onPress = { [weak self] in
            self?.statusItem.button?.title = "🔴"
            try? recorder.start()
        }
        hotkey.onRelease = { [weak self] held in
            self?.statusItem.button?.title = "🎤"
            let url = try? recorder.stop()
            NSLog("held %.2fs, wav: %@", held, url?.path ?? "nil")
        }
        if !hotkey.start() {
            NSLog("HotkeyMonitor: event tap failed — grant Accessibility and relaunch")
        }
    }
}
