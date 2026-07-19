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
