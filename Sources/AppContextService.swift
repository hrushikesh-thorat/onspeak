import Foundation
import ApplicationServices
import AppKit

struct AppSelectionSnapshot: Sendable {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
}

struct AppContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let currentActivity: String

    var contextSummary: String {
        currentActivity
    }
}

/// Collects lightweight context through the Accessibility API.
///
/// OnSpeak keeps this context entirely on-device for local workflow metadata.
final class AppContextService {
    init() {}

    func collectSelectionSnapshot() -> AppSelectionSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppSelectionSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return AppSelectionSnapshot(
            appName: frontmostApp.localizedName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: focusedWindowTitle(from: appElement) ?? frontmostApp.localizedName,
            selectedText: rawSelectedText(from: appElement)
        )
    }

    /// Captures selection state without sharing or mutating the long-lived
    /// AppState service instance. Shortcut preflight calls this from a
    /// detached task because AX queries into the focused process may block.
    static func captureSelectionSnapshot() -> AppSelectionSnapshot {
        AppContextService().collectSelectionSnapshot()
    }

    func collectContext() async -> AppContext {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                currentActivity: "Dictating in an unrecognized app."
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        let appName = frontmostApp.localizedName
        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = selectedText(from: appElement)
        let activity = [appName, windowTitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
            .joined(separator: " — ")

        return AppContext(
            appName: appName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            currentActivity: activity.isEmpty ? "Dictating in the active app." : "Dictating in \(activity)."
        )
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedWindowAttribute as CFString
        ) else {
            return nil
        }
        return accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString)
    }

    private func selectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ), let selectedText = accessibilityString(
            from: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) {
            return selectedText
        }
        return accessibilityString(from: appElement, attribute: kAXSelectedTextAttribute as CFString)
    }

    private func rawSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ), let selectedText = accessibilityRawString(
            from: focusedElement,
            attribute: kAXSelectedTextAttribute as CFString
        ) {
            return selectedText
        }
        return accessibilityRawString(from: appElement, attribute: kAXSelectedTextAttribute as CFString)
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        guard let value = accessibilityRawString(from: element, attribute: attribute) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func accessibilityRawString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String, !stringValue.isEmpty else {
            return nil
        }
        return stringValue
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
