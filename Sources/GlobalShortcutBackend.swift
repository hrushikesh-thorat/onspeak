import Cocoa
import os.log

private let shortcutLog = OSLog(subsystem: "com.rushatpeace.onspeak", category: "Shortcuts")

enum GlobalShortcutBackendError: LocalizedError {
    case accessibilityPermissionRequired
    case eventTapUnavailable
    case eventTapRunLoopSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required for global shortcuts."
        case .eventTapUnavailable:
            return "The modifier shortcut listener could not start. Restart OnSpeak after enabling Accessibility."
        case .eventTapRunLoopSourceUnavailable:
            return "Global shortcuts could not start because their run loop source could not be created."
        }
    }
}

/// Observes modifier transitions only. The active tap is gated by the
/// Accessibility permission OnSpeak already needs for pasting; ordinary
/// key-down and key-up events are deliberately excluded from its event mask.
final class GlobalShortcutBackend {
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    var onInputEvent: ((ShortcutInputEvent) -> ShortcutConsumeDecision)?

    func start() throws {
        stop()
        guard AXIsProcessTrusted() else {
            throw GlobalShortcutBackendError.accessibilityPermissionRequired
        }
        try installEventTap()
    }

    func stop() {
        tearDownEventTap()
        _ = onInputEvent?(.backendReset)
    }

    deinit {
        stop()
    }

    private func installEventTap() throws {
        let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let backend = Unmanaged<GlobalShortcutBackend>.fromOpaque(userInfo).takeUnretainedValue()
            backend.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            os_log(.error, log: shortcutLog, "Failed to install flags-only shortcut event tap")
            throw GlobalShortcutBackendError.eventTapUnavailable
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw GlobalShortcutBackendError.eventTapRunLoopSourceUnavailable
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
        os_log(.info, log: shortcutLog, "Flags-only shortcut event tap started")
    }

    private func tearDownEventTap() {
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRunLoopSource = nil
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            _ = onInputEvent?(.backendReset)
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        guard type == .flagsChanged,
              let nsEvent = NSEvent(cgEvent: event),
              ShortcutBinding.modifierKeyCodes.contains(nsEvent.keyCode),
              let isDown = ModifierKeyEventState.isKeyDown(for: nsEvent) else {
            return
        }

        os_log(.debug, log: shortcutLog, "Modifier transition keyCode=%{public}d down=%{public}d", nsEvent.keyCode, isDown)
        _ = onInputEvent?(.modifierChanged(keyCode: nsEvent.keyCode, isDown: isDown))
    }
}
