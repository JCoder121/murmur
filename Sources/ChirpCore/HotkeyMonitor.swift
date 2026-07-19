import AppKit
import CoreGraphics

public final class HotkeyMonitor {
    public var onPress: (() -> Void)?
    /// Fires once per hold when Right-Option joins the chord (or was already
    /// down at press) — the moment to start warming the smart pipeline.
    public var onSmartEngage: (() -> Void)?
    /// smart latches true if Right-Option was held at any point during the hold,
    /// so releasing the two keys in either order still counts as the chord.
    public var onRelease: ((_ held: TimeInterval, _ smart: Bool) -> Void)?

    private var tap: CFMachPort?
    private var pressedAt: Date?
    private var smartLatched = false
    private static let rightCmdKeycode: Int64 = 54
    private static let rightCmdDeviceMask: UInt64 = 0x10  // NX_DEVICERCMDKEYMASK: right-Cmd's own device bit
    private static let rightOptDeviceMask: UInt64 = 0x40  // NX_DEVICERALTKEYMASK: right-Option's own device bit

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
        let optDown = event.flags.rawValue & Self.rightOptDeviceMask != 0
        if pressedAt != nil, optDown, !smartLatched {
            smartLatched = true
            onSmartEngage?()
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Self.rightCmdKeycode else { return }
        let isDown = event.flags.rawValue & Self.rightCmdDeviceMask != 0
        if isDown, pressedAt == nil {
            pressedAt = Date()
            onPress?()
            if optDown {  // option was already held when cmd went down
                smartLatched = true
                onSmartEngage?()
            }
        } else if !isDown, let start = pressedAt {
            pressedAt = nil
            let smart = smartLatched
            smartLatched = false
            onRelease?(Date().timeIntervalSince(start), smart)
        }
    }
}
