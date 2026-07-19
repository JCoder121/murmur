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
