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
