import Foundation

/// Identifies one recording attempt and provides monotonic elapsed timing for
/// latency milestones. The context is transient and must not be persisted.
struct LiveTranscriptSessionContext: Equatable, Sendable {
    let id: UUID
    let startedAtUptime: TimeInterval

    init(
        id: UUID = UUID(),
        startedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.id = id
        self.startedAtUptime = startedAtUptime
    }

    /// Whole milliseconds since this session began, using the same monotonic
    /// uptime clock as `startedAtUptime`. A clock value earlier than the start
    /// is treated as zero elapsed time.
    func elapsedMilliseconds(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Int {
        Int(max(0, now - startedAtUptime) * 1_000)
    }
}

/// Tracks which recording session may still deliver asynchronous work.
struct LiveTranscriptSessionGate: Sendable {
    private(set) var activeContext: LiveTranscriptSessionContext?

    var activeSessionID: UUID? {
        activeContext?.id
    }

    mutating func begin(_ context: LiveTranscriptSessionContext) {
        activeContext = context
    }

    mutating func invalidate() {
        activeContext = nil
    }

    /// Invalidates only the named session. Returns whether it was current.
    @discardableResult
    mutating func invalidate(matching sessionID: UUID) -> Bool {
        guard accepts(sessionID: sessionID) else { return false }
        invalidate()
        return true
    }

    func accepts(sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }
}

/// Decides whether shortcut preflight needs an Accessibility selection query.
enum SelectionSnapshotPolicy: Sendable {
    static func requiresSnapshot(
        editModeEnabled: Bool,
        usesAutomaticStyle: Bool,
        manualCommandRequested: Bool
    ) -> Bool {
        guard editModeEnabled else { return false }
        return usesAutomaticStyle || manualCommandRequested
    }
}

/// The setup attempts a streaming session may make. Keeping the plan pure
/// makes the preview-off and accurate-only fallback invariants testable
/// without importing the Speech framework into the lightweight test runner.
enum SpeechAnalyzerStreamingAttempt: Equatable, Sendable {
    case accurateAndPreview
    case accurateOnly
}

enum SpeechAnalyzerStreamingStartupPlan: Sendable {
    static func attempts(previewEnabled: Bool) -> [SpeechAnalyzerStreamingAttempt] {
        previewEnabled ? [.accurateAndPreview, .accurateOnly] : [.accurateOnly]
    }
}

/// Queue-confined coalescing state for live-preview delivery. Only the newest
/// value is retained while a main-queue callback is pending.
struct LiveTranscriptDeliveryLatch: Sendable {
    private(set) var pendingSessionID: UUID?
    private(set) var pendingText: String?
    private(set) var isDeliveryScheduled = false

    /// Stores the newest value and reports whether a main-queue delivery must
    /// be scheduled. Subsequent values replace the payload without scheduling
    /// more work.
    mutating func enqueue(sessionID: UUID, text: String) -> Bool {
        pendingSessionID = sessionID
        pendingText = text
        guard !isDeliveryScheduled else { return false }
        isDeliveryScheduled = true
        return true
    }

    /// Takes the newest pending value and opens the latch for another queued
    /// delivery. The two fields are either returned together or not at all.
    mutating func take() -> (sessionID: UUID, text: String)? {
        defer {
            pendingSessionID = nil
            pendingText = nil
            isDeliveryScheduled = false
        }
        guard let pendingSessionID, let pendingText else { return nil }
        return (pendingSessionID, pendingText)
    }

    mutating func cancel() {
        pendingSessionID = nil
        pendingText = nil
        isDeliveryScheduled = false
    }
}
