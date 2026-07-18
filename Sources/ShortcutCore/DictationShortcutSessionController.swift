import Foundation

enum DictationShortcutAction: Equatable {
    case start(RecordingTriggerMode)
    case stop
}

final class DictationShortcutSessionController {
    private(set) var activeMode: RecordingTriggerMode?

    func handle(event: ShortcutEvent, isTranscribing: Bool) -> DictationShortcutAction? {
        if event == .copyAgainTriggered { return nil }

        if activeMode == nil {
            guard !isTranscribing, event == .holdActivated else { return nil }
            activeMode = .hold
            return .start(.hold)
        }

        guard activeMode == .hold, event == .holdDeactivated else { return nil }
        reset()
        return .stop
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
    }

    func reset() {
        activeMode = nil
    }
}
