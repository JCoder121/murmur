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
