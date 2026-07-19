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
