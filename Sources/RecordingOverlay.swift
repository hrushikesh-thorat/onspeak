import SwiftUI
import AppKit
import os.log

private let recordingOverlayLog = OSLog(
    subsystem: "com.rushatpeace.onspeak",
    category: "RecordingOverlay"
)

// MARK: - State

final class RecordingOverlayState: ObservableObject {
    @Published var phase: OverlayPhase = .recording
    @Published var audioLevel: Float = 0.0
    @Published var recordingTriggerMode: RecordingTriggerMode = .hold
    @Published var isCommandMode = false
    @Published var updateVersion: String = ""
    @Published var errorMessage: String?
    @Published var toastID: UUID?
    @Published var liveTranscript: String = ""
    @Published var targetApplicationName: String = "Current App"
    @Published var targetApplicationIcon: NSImage?
}

enum OverlayPhase {
    case initializing
    case recording
    case transcribing
    case feedback
    case updateAvailable
}

// MARK: - NSScreen Helpers

extension NSScreen {
    /// CoreGraphics display identifier for this screen, or nil if the
    /// device description is missing the key (vanishingly rare). Stable
    /// across screen-arrangement changes for as long as the display is
    /// connected, which is what the overlay picker stores in UserDefaults.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

// MARK: - Panel Helpers

private func makeOverlayPanel(width: CGFloat, height: CGFloat) -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: width, height: height),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.level = .screenSaver
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces]
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    return panel
}

private func makeNotchContent<V: View>(
    width: CGFloat,
    height: CGFloat,
    cornerRadius: CGFloat,
    showsSiriBorder: Bool,
    rootView: V
) -> NSView {
    let shape = UnevenRoundedRectangle(
        bottomLeadingRadius: cornerRadius,
        bottomTrailingRadius: cornerRadius
    )
    let shaped = ZStack {
        rootView
            .frame(width: width, height: height)
            .background(Color.black)

        if showsSiriBorder {
            SiriNotchBorder(cornerRadius: cornerRadius)
        }
    }
    .frame(width: width, height: height)
    .clipShape(shape)

    let hosting = NSHostingView(rootView: shaped)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.autoresizingMask = [.width, .height]
    return hosting
}

private func makeBottomCardContent<V: View>(
    width: CGFloat,
    height: CGFloat,
    showsSiriBorder: Bool,
    rootView: V
) -> NSView {
    let glowInset: CGFloat = 6
    let cardWidth = max(0, width - glowInset * 2)
    let cardHeight = max(0, height - glowInset * 2)
    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    let shaped = ZStack {
        rootView
            .frame(width: cardWidth, height: cardHeight)
            .background(Color(red: 0.105, green: 0.105, blue: 0.115))
            .clipShape(shape)

        if showsSiriBorder {
            SiriFloatingCardBorder()
                .frame(width: cardWidth, height: cardHeight)
        }
    }
    .frame(width: width, height: height)

    let hosting = NSHostingView(rootView: shaped)
    hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
    hosting.autoresizingMask = [.width, .height]
    return hosting
}

/// A low-key Siri-inspired rim whose blue, violet, and pink highlights travel
/// around the island without changing its geometry or covering its content.
private struct SiriNotchBorder: View {
    let cornerRadius: CGFloat

    private let colors: [Color] = [
        Color(red: 0.18, green: 0.72, blue: 1.00),
        Color(red: 0.47, green: 0.31, blue: 1.00),
        Color(red: 0.98, green: 0.24, blue: 0.70),
        Color(red: 0.35, green: 0.78, blue: 1.00),
        Color(red: 0.18, green: 0.72, blue: 1.00),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let cycle = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 7.0)
            let phase = cycle / 7.0 * 360
            SiriNotchRimShape(cornerRadius: cornerRadius)
                .stroke(
                    AngularGradient(
                        colors: colors,
                        center: .center,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    ),
                    style: StrokeStyle(
                        lineWidth: 2.25,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: Color.purple.opacity(0.45), radius: 3)
                .shadow(color: Color.blue.opacity(0.28), radius: 5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Open outline for the island's sides and rounded bottom. The top edge stays
/// unadorned so it visually merges with the black display bezel/notch area.
private struct SiriNotchRimShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset: CGFloat = 1.25
        let radius = min(cornerRadius, max(0, rect.width / 2 - inset))
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let bottom = rect.maxY - inset

        var path = Path()
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: bottom),
            control: CGPoint(x: left, y: bottom)
        )
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: right, y: bottom - radius),
            control: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY))
        return path
    }
}

/// Full animated rim for the floating card. Unlike the top-mounted notch,
/// every edge is visible because the card sits away from the screen bezel.
private struct SiriFloatingCardBorder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let segmentLength: CGFloat = 0.5
    private let featherLength: CGFloat = 0.0625
    private let featherSteps = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let phase = reduceMotion
                ? 0.0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 7.0) / 7.0

            Canvas { context, size in
                let perimeter = RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .path(in: CGRect(origin: .zero, size: size))
                let stroke = StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round)

                drawSegment(
                    in: &context,
                    path: perimeter,
                    from: phase,
                    length: featherLength,
                    steps: featherSteps,
                    opacity: { progress in 0.9 * progress },
                    stroke: stroke
                )
                drawSegment(
                    in: &context,
                    path: perimeter,
                    from: phase + featherLength,
                    length: segmentLength - featherLength * 2,
                    steps: 1,
                    opacity: { _ in 0.9 },
                    stroke: stroke
                )
                drawSegment(
                    in: &context,
                    path: perimeter,
                    from: phase + segmentLength - featherLength,
                    length: featherLength,
                    steps: featherSteps,
                    opacity: { progress in 0.9 * (1 - progress) },
                    stroke: stroke
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawSegment(
        in context: inout GraphicsContext,
        path: Path,
        from start: Double,
        length: CGFloat,
        steps: Int,
        opacity: (CGFloat) -> CGFloat,
        stroke: StrokeStyle
    ) {
        for index in 0..<steps {
            let lower = CGFloat(index) / CGFloat(steps)
            let upper = CGFloat(index + 1) / CGFloat(steps)
            let startPosition = start + Double(length * lower)
            let endPosition = start + Double(length * upper)
            let segmentOpacity = opacity((lower + upper) / 2)

            drawWrappedPath(
                in: &context,
                path: path,
                from: startPosition,
                to: endPosition,
                opacity: segmentOpacity,
                stroke: stroke
            )
        }
    }

    private func drawWrappedPath(
        in context: inout GraphicsContext,
        path: Path,
        from start: Double,
        to end: Double,
        opacity: CGFloat,
        stroke: StrokeStyle
    ) {
        let normalizedStart = start.truncatingRemainder(dividingBy: 1)
        let normalizedEnd = end.truncatingRemainder(dividingBy: 1)
        let shading = GraphicsContext.Shading.color(.white.opacity(opacity))

        if normalizedStart <= normalizedEnd, end - start < 1 {
            context.stroke(
                path.trimmedPath(from: normalizedStart, to: normalizedEnd),
                with: shading,
                style: stroke
            )
        } else {
            context.stroke(
                path.trimmedPath(from: normalizedStart, to: 1),
                with: shading,
                style: stroke
            )
            context.stroke(
                path.trimmedPath(from: 0, to: normalizedEnd),
                with: shading,
                style: stroke
            )
        }
    }
}

// MARK: - Manager

final class RecordingOverlayManager {
    private var overlayWindow: NSPanel?
    private let overlayState = RecordingOverlayState()
    private var lockedOverlayWidth: CGFloat?
    private var hasExpandedForLiveTranscript = false
    private var liveTranscriptSessionGate = LiveTranscriptSessionGate()
    private var didLogFirstPanelForActiveSession = false
    private var didLogFirstPreviewApplicationForActiveSession = false

    var activeRecordingSessionID: UUID? {
        liveTranscriptSessionGate.activeSessionID
    }

    fileprivate static let liveTranscriptStripHeight: CGFloat = 64
    private static let maximumLiveTranscriptWidth: CGFloat = 420
    private static let bottomCardWidth: CGFloat = 336
    private static let bottomCardHeight: CGFloat = 124
    private static let bottomCardCompactHeight: CGFloat = 64

    var onStopButtonPressed: (() -> Void)?
    var onCancelButtonPressed: (() -> Void)?
    var onUpdateOverlayPressed: (() -> Void)?

    /// The screen the overlay should drop down on. The user picks one of
    /// three modes in Settings, stored in UserDefaults under
    /// `overlay_display_id`:
    ///
    /// - `0` (default) — Active window: follows focus across monitors via
    ///   NSScreen.main. Default for backward compatibility — the original
    ///   behavior on a single-display setup is unchanged.
    /// - `-1` — Primary display: always NSScreen.screens.first (the display
    ///   designated as primary in System Settings → Displays).
    /// - any positive integer — specific NSScreen displayID. Falls back to
    ///   primary if that display is unplugged.
    private var targetScreen: NSScreen? {
        let savedID = UserDefaults.standard.integer(forKey: "overlay_display_id")
        switch savedID {
        case 0:
            return NSScreen.main ?? NSScreen.screens.first
        case -1:
            return NSScreen.screens.first ?? NSScreen.main
        default:
            if let match = NSScreen.screens.first(where: { Int($0.displayID ?? 0) == savedID }) {
                return match
            }
            return NSScreen.screens.first ?? NSScreen.main
        }
    }

    private var screenHasNotch: Bool {
        guard let screen = targetScreen else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidth: CGFloat {
        guard let screen = targetScreen, screenHasNotch else { return 0 }
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else { return 0 }
        return screen.frame.width - leftArea.width - rightArea.width
    }

    private var notchOverlap: CGFloat {
        guard let screen = targetScreen else { return 0 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    private var overlayAcceptsMouseEvents: Bool {
        if usesBottomListeningCard {
            switch overlayState.phase {
            case .initializing, .recording, .transcribing, .updateAvailable:
                return true
            case .feedback:
                return false
            }
        }
        return (overlayState.phase == .recording && overlayState.recordingTriggerMode == .manual)
            || overlayState.phase == .updateAvailable
    }

    /// New and existing installs default to the bottom card. The menu-bar/notch
    /// presentation remains available as an explicit alternate style.
    private var usesBottomListeningCard: Bool {
        (UserDefaults.standard.object(forKey: "use_bottom_listening_card") as? Bool) ?? true
    }

    /// Establishes the overlay boundary for one real recording attempt before
    /// any asynchronous preflight or analyzer work begins. The session is
    /// installed synchronously on the main thread so matching preview results
    /// can be retained immediately, even if AppKit has not produced a panel.
    func beginRecordingSession(
        id: UUID,
        mode: RecordingTriggerMode,
        isCommandMode: Bool
    ) {
        beginRecordingSession(
            context: LiveTranscriptSessionContext(id: id),
            mode: mode,
            isCommandMode: isCommandMode
        )
    }

    /// Context-based form used by real recordings so overlay milestone timing
    /// shares the shortcut-acceptance clock with capture and transcription.
    func beginRecordingSession(
        context: LiveTranscriptSessionContext,
        mode: RecordingTriggerMode,
        isCommandMode: Bool
    ) {
        performOnMainSynchronously {
            self.lockedOverlayWidth = nil
            self.clearLiveTranscriptSession()
            self.captureTargetApplication()
            self.liveTranscriptSessionGate.begin(context)
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .initializing
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: false)
        }
    }

    func showInitializing(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.clearLiveTranscriptSession()
            self.captureTargetApplication()
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .initializing
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: false)
        }
    }

    func showRecording(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.clearLiveTranscriptSession()
            self.captureTargetApplication()
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .recording
            self.overlayState.audioLevel = 0
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func transitionToRecording(mode: RecordingTriggerMode = .hold, isCommandMode: Bool = false) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.overlayState.recordingTriggerMode = mode
            self.overlayState.isCommandMode = isCommandMode
            self.overlayState.phase = .recording
            self.updateOverlayLayout(animated: true)
        }
    }

    func setRecordingTriggerMode(_ mode: RecordingTriggerMode, animated: Bool) {
        DispatchQueue.main.async {
            self.overlayState.recordingTriggerMode = mode
            self.updateOverlayLayout(animated: animated)
        }
    }

    func updateAudioLevel(_ level: Float) {
        DispatchQueue.main.async {
            self.overlayState.audioLevel = level
        }
    }

    func updateLiveTranscript(_ text: String, sessionID: UUID) {
        DispatchQueue.main.async {
            // Check identity when the queued UI work executes, not when it is
            // submitted. A dismissal or replacement that wins the race makes
            // an already-queued delivery stale.
            guard self.liveTranscriptSessionGate.accepts(sessionID: sessionID) else {
                return
            }
            switch self.overlayState.phase {
            case .initializing, .recording, .transcribing:
                break
            case .feedback, .updateAvailable:
                return
            }

            self.overlayState.liveTranscript = text
            guard !text.isEmpty, !self.hasExpandedForLiveTranscript else { return }

            self.hasExpandedForLiveTranscript = true
            if self.overlayState.phase == .transcribing, let screen = self.targetScreen {
                self.lockedOverlayWidth = self.liveTranscriptWidth(on: screen)
            }
            self.updateOverlayLayout(animated: true)
            self.logFirstPreviewApplicationIfNeeded()
        }
    }

    func showTranscribing() {
        DispatchQueue.main.async {
            self.setTranscribingPhase()
        }
    }

    func showFailureIndicator() {
        DispatchQueue.main.async {
            self.showFeedbackPanel()
        }
    }

    /// Maximum length of an in-pill error message. Anything longer is
    /// truncated with an ellipsis to keep the pill from stretching across
    /// the menu bar; the full text remains available in `os_log` for
    /// forensic review.
    private static let maxToastMessageLength = 90

    /// Surface a transient error in the menu-bar pill. The pill resizes to
    /// fit the message (subject to the truncation cap), holds for a few
    /// seconds, then dismisses. Intended for non-fatal user-facing errors
    /// that previously only landed in `os_log` — rate limits, network
    /// failures, permission gaps, etc.
    func showError(_ message: String) {
        let truncated: String = {
            if message.count <= Self.maxToastMessageLength { return message }
            let cutoff = message.index(message.startIndex, offsetBy: Self.maxToastMessageLength - 1)
            return String(message[..<cutoff]) + "…"
        }()
        DispatchQueue.main.async {
            let toastID = UUID()
            self.clearLiveTranscriptSession()
            self.overlayState.errorMessage = truncated
            self.overlayState.toastID = toastID
            self.lockedOverlayWidth = nil
            self.overlayState.phase = .feedback
            self.showOverlayPanel(animatedResize: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                guard self.overlayState.phase == .feedback,
                      self.overlayState.errorMessage == truncated,
                      self.overlayState.toastID == toastID else {
                    return
                }
                self.overlayState.errorMessage = nil
                self.overlayState.toastID = nil
                self.dismissAll()
            }
        }
    }

    func showUpdateAvailable(version: String) {
        DispatchQueue.main.async {
            self.lockedOverlayWidth = nil
            self.clearLiveTranscriptSession()
            self.overlayState.isCommandMode = false
            self.overlayState.updateVersion = version
            self.overlayState.phase = .updateAvailable
            self.showOverlayPanel(animatedResize: true)
        }
    }

    func dismissUpdateAvailable(version: String) {
        DispatchQueue.main.async {
            guard self.overlayState.phase == .updateAvailable,
                  self.overlayState.updateVersion == version else {
                return
            }
            self.dismissAll()
        }
    }

    func dismiss() {
        performOnMainSynchronously {
            self.dismissAll()
        }
    }

    private func showOverlayPanel(animatedResize: Bool) {
        let frame = overlayFrame

        if let panel = overlayWindow {
            panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
            panel.contentView = makeOverlayContent(frame: frame)
            resize(panel: panel, to: frame, animated: animatedResize)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            logFirstPanelOrderedIfNeeded()
            logFirstPreviewApplicationIfNeeded()
            return
        }

        let panel = makeOverlayPanel(width: frame.width, height: frame.height)
        panel.hasShadow = false
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)

        guard let screen = targetScreen else { return }

        let hiddenY = usesBottomListeningCard
            ? screen.frame.minY - frame.height
            : screen.frame.maxY
        let hiddenFrame = NSRect(
            x: frame.origin.x,
            y: hiddenY,
            width: frame.width,
            height: frame.height
        )
        panel.setFrame(hiddenFrame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            panel.animator().setFrame(frame, display: true)
        }

        overlayWindow = panel
        logFirstPanelOrderedIfNeeded()
        logFirstPreviewApplicationIfNeeded()
    }

    private func updateOverlayLayout(animated: Bool) {
        guard let panel = overlayWindow else { return }
        let frame = overlayFrame
        panel.ignoresMouseEvents = !overlayAcceptsMouseEvents
        panel.contentView = makeOverlayContent(frame: frame)
        resize(panel: panel, to: frame, animated: animated)
    }

    private func setTranscribingPhase() {
        if usesBottomListeningCard, let screen = targetScreen {
            lockedOverlayWidth = bottomCardWidth(on: screen)
        } else if hasExpandedForLiveTranscript, let screen = targetScreen {
            lockedOverlayWidth = liveTranscriptWidth(on: screen)
        } else {
            lockedOverlayWidth = overlayWindow?.frame.width ?? overlayWidth
        }
        overlayState.phase = .transcribing
        showOverlayPanel(animatedResize: true)
    }

    private func makeOverlayContent(frame: NSRect) -> NSView {
        if usesBottomListeningCard {
            let rootView = BottomListeningCardView(
                state: overlayState,
                showsLiveTranscript: hasExpandedForLiveTranscript,
                onStopButtonPressed: { [weak self] in
                    self?.onStopButtonPressed?()
                },
                onCancelButtonPressed: { [weak self] in
                    self?.onCancelButtonPressed?()
                },
                onUpdateOverlayPressed: { [weak self] in
                    self?.onUpdateOverlayPressed?()
                }
            )
            return makeBottomCardContent(
                width: frame.width,
                height: frame.height,
                showsSiriBorder: liveTranscriptSessionGate.activeContext != nil,
                rootView: AnyView(rootView)
            )
        }

        if useWingedLayout {
            // Winged layout: notch x-range stays solid black so the cutout masks it.
            let rootView = WingedRecordingView(
                state: overlayState,
                leftWingWidth: Self.leftWingWidth,
                notchWidth: notchWidth,
                rightWingWidth: Self.rightWingWidth,
                wingsRowHeight: notchOverlap,
                showsLiveTranscript: hasExpandedForLiveTranscript,
                onStopButtonPressed: { [weak self] in
                    self?.onStopButtonPressed?()
                }
            )
            return makeNotchContent(
                width: frame.width,
                height: frame.height,
                cornerRadius: 14,
                showsSiriBorder: hasExpandedForLiveTranscript,
                rootView: AnyView(rootView)
            )
        }

        return makeNotchContent(
            width: frame.width,
            height: frame.height,
            cornerRadius: screenHasNotch ? 18 : 12,
            showsSiriBorder: hasExpandedForLiveTranscript,
            rootView: AnyView(
                RecordingOverlayView(
                    state: overlayState,
                    contentRowHeight: max(
                        0,
                        frame.height
                            - (screenHasNotch ? notchOverlap : 0)
                            - (hasExpandedForLiveTranscript ? Self.liveTranscriptStripHeight : 0)
                    ),
                    showsLiveTranscript: hasExpandedForLiveTranscript,
                    onStopButtonPressed: { [weak self] in
                        self?.onStopButtonPressed?()
                    },
                    onUpdateOverlayPressed: { [weak self] in
                        self?.onUpdateOverlayPressed?()
                    }
                )
                .padding(.top, screenHasNotch ? notchOverlap : 0)
            )
        )
    }

    private func resize(panel: NSPanel, to frame: NSRect, animated: Bool) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// True iff the alternate menu-bar style is selected on a notched display.
    /// Update and error states still use their compact pill presentation.
    private var useWingedLayout: Bool {
        guard !usesBottomListeningCard else { return false }
        guard screenHasNotch else { return false }
        switch overlayState.phase {
        case .recording, .initializing, .transcribing:
            return true
        case .feedback:
            return overlayState.errorMessage?.isEmpty ?? true
        case .updateAvailable:
            return false
        }
    }

    /// Wing width — tight to the compact waveform / stop button so the
    /// panel stays clear of right-side menu-bar items.
    static let wingWidth: CGFloat = 36
    static let leftWingWidth: CGFloat = wingWidth
    static let rightWingWidth: CGFloat = wingWidth

    private var overlayFrame: NSRect {
        guard let screen = targetScreen else { return .zero }

        if usesBottomListeningCard {
            let isCompactPhase: Bool
            switch overlayState.phase {
            case .feedback, .updateAvailable:
                isCompactPhase = true
            case .initializing, .recording, .transcribing:
                isCompactPhase = false
            }
            let width = isCompactPhase ? overlayWidth : bottomCardWidth(on: screen)
            let height = isCompactPhase
                ? Self.bottomCardCompactHeight
                : Self.bottomCardHeight
            let x = screen.visibleFrame.midX - width / 2
            let y = screen.visibleFrame.minY + 24
            return NSRect(x: x, y: y, width: width, height: height)
        }

        if useWingedLayout {
            // Anchor to the screen's auxiliary-area boundaries of the notch;
            // when the preview is expanded, center the wider panel on the
            // physical notch so the fixed-width spacer remains aligned.
            let nWidth = notchWidth
            let nLeftX = screen.auxiliaryTopLeftArea?.maxX
                ?? (screen.frame.midX - nWidth / 2)
            let leftWing = Self.leftWingWidth
            let rightWing = Self.rightWingWidth
            let baseWidth = leftWing + nWidth + rightWing
            let panelHeight = notchOverlap
                + (hasExpandedForLiveTranscript ? Self.liveTranscriptStripHeight : 0)
            let panelWidth: CGFloat
            if overlayState.phase == .transcribing, let lockedOverlayWidth {
                panelWidth = lockedOverlayWidth
            } else if hasExpandedForLiveTranscript {
                panelWidth = liveTranscriptWidth(on: screen)
            } else {
                panelWidth = baseWidth
            }
            let notchCenterX = nLeftX + nWidth / 2
            let panelX = notchCenterX - panelWidth / 2
            let panelY = screen.frame.maxY - panelHeight
            return NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)
        }

        let width = overlayWidth
        let useCompact = (UserDefaults.standard.object(forKey: "use_compact_overlay") as? Bool) ?? true
        let forceDropDownPill = overlayState.phase == .feedback
            && !(overlayState.errorMessage?.isEmpty ?? true)
        // Compact mode: overlay sits flush with the menu bar on every display.
        // notchOverlap equals the menu-bar height on non-notched screens too,
        // so zero protrusion is universal — not notch-only. The legacy
        // 38pt drop-down pill remains available when use_compact_overlay
        // is explicitly toggled off. Error toasts also force the drop-down
        // height so messages stay readable even when compact overlay is enabled.
        let baseHeight: CGFloat = (useCompact && !forceDropDownPill)
            ? notchOverlap
            : 38 + (screenHasNotch ? notchOverlap : 0)
        let height = baseHeight
            + (hasExpandedForLiveTranscript ? Self.liveTranscriptStripHeight : 0)
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        if let lockedOverlayWidth, overlayState.phase == .transcribing {
            return lockedOverlayWidth
        }

        if overlayState.phase == .feedback {
            // Error toasts size to the message length so short messages do
            // not get the same wide pill as long ones. ~6.8pt per character
            // plus 60pt of icon and padding chrome, clamped to 180-420pt so
            // very short messages stay readable and very long ones do not
            // stretch the pill across the menu bar. Bare failure-X marker
            // (no message) keeps the original 92pt.
            let feedbackWidth: CGFloat = {
                guard let msg = overlayState.errorMessage, !msg.isEmpty else {
                    return 92
                }
                let estimated = CGFloat(msg.count) * 6.8 + 60
                return min(420, max(180, estimated))
            }()
            guard screenHasNotch else { return feedbackWidth }
            return max(notchWidth, feedbackWidth)
        }

        if overlayState.phase == .updateAvailable {
            let updateWidth: CGFloat = 190
            guard screenHasNotch else { return updateWidth }
            return max(notchWidth, updateWidth)
        }

        if hasExpandedForLiveTranscript, let screen = targetScreen {
            return liveTranscriptWidth(on: screen)
        }

        let commandModeWidth: CGFloat = 180
        let manualWidth: CGFloat = 150
        let defaultWidth: CGFloat = 92
        let baseWidth: CGFloat

        if overlayState.isCommandMode {
            baseWidth = commandModeWidth
        } else if overlayState.phase == .recording && overlayState.recordingTriggerMode == .manual {
            baseWidth = manualWidth
        } else {
            baseWidth = defaultWidth
        }

        guard screenHasNotch else { return baseWidth }
        return max(notchWidth, baseWidth)
    }

    private func showFeedbackPanel() {
        lockedOverlayWidth = nil
        clearLiveTranscriptSession()
        overlayState.phase = .feedback
        showOverlayPanel(animatedResize: true)
    }

    private func dismissAll() {
        lockedOverlayWidth = nil
        clearLiveTranscriptSession()
        overlayState.isCommandMode = false
        overlayState.updateVersion = ""
        if let panel = overlayWindow {
            panel.orderOut(nil)
            // orderOut alone leaves the panel retained in NSApp.windows with its
            // SwiftUI hierarchy mounted — repeatForever animations keep flushing
            // Core Animation forever. Unmount and close so the panel deallocates.
            panel.contentView = nil
            panel.close()
            overlayWindow = nil
        }
    }

    private func liveTranscriptWidth(on screen: NSScreen) -> CGFloat {
        min(Self.maximumLiveTranscriptWidth, screen.visibleFrame.width - 40)
    }

    private func bottomCardWidth(on screen: NSScreen) -> CGFloat {
        min(Self.bottomCardWidth, screen.visibleFrame.width - 40)
    }

    private func captureTargetApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            overlayState.targetApplicationName = "Current App"
            overlayState.targetApplicationIcon = nil
            return
        }
        overlayState.targetApplicationName = application.localizedName ?? "Current App"
        overlayState.targetApplicationIcon = application.icon
    }

    private func clearLiveTranscriptSession() {
        liveTranscriptSessionGate.invalidate()
        didLogFirstPanelForActiveSession = false
        didLogFirstPreviewApplicationForActiveSession = false
        resetLiveTranscriptPresentation()
    }

    private func resetLiveTranscriptPresentation() {
        overlayState.liveTranscript = ""
        hasExpandedForLiveTranscript = false
    }

    private func logFirstPanelOrderedIfNeeded() {
        guard !didLogFirstPanelForActiveSession,
              let context = liveTranscriptSessionGate.activeContext else {
            return
        }
        didLogFirstPanelForActiveSession = true
        os_log(
            .info,
            log: recordingOverlayLog,
            "session %{public}@ initializing panel ordered front at %{public}d ms",
            context.id.uuidString,
            context.elapsedMilliseconds()
        )
    }

    private func logFirstPreviewApplicationIfNeeded() {
        guard !didLogFirstPreviewApplicationForActiveSession,
              overlayWindow != nil,
              hasExpandedForLiveTranscript,
              !overlayState.liveTranscript.isEmpty,
              let context = liveTranscriptSessionGate.activeContext else {
            return
        }
        didLogFirstPreviewApplicationForActiveSession = true
        os_log(
            .info,
            log: recordingOverlayLog,
            "session %{public}@ first preview row applied at %{public}d ms",
            context.id.uuidString,
            context.elapsedMilliseconds()
        )
    }

    private func performOnMainSynchronously(_ work: () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }
}

// MARK: - Winged Recording View

/// Wing layout: waveform left, stop button right, solid-black notch in the middle
/// (the camera cutout masks those pixels).
struct WingedRecordingView: View {
    @ObservedObject var state: RecordingOverlayState
    let leftWingWidth: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let wingsRowHeight: CGFloat
    let showsLiveTranscript: Bool
    let onStopButtonPressed: () -> Void

    private var showsLiveRecordingContent: Bool {
        state.phase == .recording
    }

    private var showsStopButton: Bool {
        showsLiveRecordingContent && state.recordingTriggerMode == .manual
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                wingsHStack

                if showsLiveTranscript && showsLiveRecordingContent {
                    OnSpeakOverlayBrand(
                        audioLevel: state.audioLevel,
                        isActive: state.phase == .recording
                    )
                        .padding(.leading, 14)
                        .transition(.opacity)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(height: wingsRowHeight)

            if showsLiveTranscript {
                LiveTranscriptStrip(text: state.liveTranscript)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
    }

    private var wingsHStack: some View {
        HStack(spacing: 0) {
            // Left wing — empty during feedback so the right-wing X reads as the sole signal.
            HStack {
                Spacer(minLength: 0)
                Group {
                    if state.phase == .feedback {
                        Color.clear
                    } else if state.phase == .initializing {
                        InitializingDotsView()
                            .transition(.opacity)
                    } else if showsLiveRecordingContent {
                        Group {
                            if showsLiveTranscript {
                                Color.clear
                            } else {
                                // Command-mode pencil sits directly above and centered
                                // over the compact waveform inside the same wing.
                                VStack(spacing: 1) {
                                    if state.isCommandMode {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white.opacity(0.92))
                                            .transition(.opacity)
                                    }
                                    CompactWaveformView(
                                        audioLevel: state.audioLevel,
                                        showsActivityPulse: state.phase == .recording
                                    )
                                }
                            }
                        }
                        .transition(.opacity)
                    } else {
                        CompactProcessingIndicatorView()
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: leftWingWidth, height: wingsRowHeight)

            // Notch spacer — solid black; camera cutout hides it.
            Color.black
                .frame(width: notchWidth, height: wingsRowHeight)

            // Right wing — stop button (recording) OR failure X (feedback),
            // horizontally centered.
            HStack {
                Spacer(minLength: 0)
                Group {
                    if state.phase == .feedback {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(Color.red.opacity(0.92)))
                            .transition(.opacity)
                    } else if showsStopButton {
                        Button(action: onStopButtonPressed) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 14, height: 14)
                                .background(Circle().fill(Color.red.opacity(0.92)))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: rightWingWidth, height: wingsRowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
    }
}

// MARK: - Live Transcript Preview

/// A display-only, three-line viewport shared by both overlay layouts. Text
/// wraps at the fixed overlay width and follows the newest lines with a short
/// animated vertical scroll, avoiding the full-line horizontal jump caused by
/// the original intrinsic-width implementation.
struct LiveTranscriptStrip: View {
    let text: String

    private let bottomAnchor = "live-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentTransition(.interpolate)

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .frame(maxWidth: .infinity, minHeight: 51, alignment: .top)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onChange(of: text) { _, _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(bottomAnchor, anchor: .bottom)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(height: RecordingOverlayManager.liveTranscriptStripHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Waveform Views

struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 22

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct WaveformView: View {
    let audioLevel: Float
    var showsActivityPulse = false

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        Group {
            if showsActivityPulse {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    waveformBars(pulseTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                waveformBars(pulseTime: nil)
            }
        }
        .frame(height: 24)
    }

    private func waveformBars(pulseTime: TimeInterval?) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index, pulseTime: pulseTime))
                    .animation(
                        .spring(
                            response: barResponse(for: index),
                            dampingFraction: 0.88
                        )
                        .delay(barDelay(for: index)),
                        value: audioLevel
                    )
            }
        }
    }

    private func barAmplitude(for index: Int, pulseTime: TimeInterval?) -> CGFloat {
        let level = CGFloat(max(audioLevel, 0))
        let baseAmplitude = min(level * Self.multipliers[index], 1.0)

        guard let pulseTime else { return baseAmplitude }

        let travelingWave = CGFloat(0.5 + 0.5 * sin((pulseTime * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((pulseTime * 3.1) + Double(index) * 0.5))
        let pulse = travelingWave * 0.22 + shimmer * 0.06

        let saturationRelief = baseAmplitude * (0.74 + pulse)
        let quietPulse = (1.0 - baseAmplitude) * (0.04 + pulse * 0.28)
        return min(saturationRelief + quietPulse, 1.0)
    }

    private func barResponse(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        let normalizedDistance = distance / Self.centerIndex
        return 0.18 + Double(normalizedDistance) * 0.06
    }

    private func barDelay(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        return Double(distance) * 0.01
    }
}

/// Tighter 5-bar waveform sized for the 36pt wing layout.
struct CompactWaveformView: View {
    let audioLevel: Float
    var showsActivityPulse = false

    private static let barCount = 5
    private static let multipliers: [CGFloat] = [0.5, 0.75, 1.0, 0.75, 0.5]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        Group {
            if showsActivityPulse {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                    bars(pulseTime: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                bars(pulseTime: nil)
            }
        }
        .frame(height: 18)
    }

    private func bars(pulseTime: TimeInterval?) -> some View {
        HStack(spacing: 1.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                CompactWaveformBar(amplitude: amplitude(for: index, pulseTime: pulseTime))
                    .animation(
                        .spring(response: 0.18, dampingFraction: 0.88),
                        value: audioLevel
                    )
            }
        }
    }

    private func amplitude(for index: Int, pulseTime: TimeInterval?) -> CGFloat {
        let level = CGFloat(max(audioLevel, 0))
        let base = min(level * Self.multipliers[index], 1.0)
        guard let pulseTime else { return base }
        let traveling = CGFloat(0.5 + 0.5 * sin((pulseTime * 6.2) - Double(index) * 0.78))
        let shimmer = CGFloat(0.5 + 0.5 * sin((pulseTime * 3.1) + Double(index) * 0.5))
        let pulse = traveling * 0.22 + shimmer * 0.06
        let saturationRelief = base * (0.74 + pulse)
        let quietPulse = (1.0 - base) * (0.04 + pulse * 0.28)
        return min(saturationRelief + quietPulse, 1.0)
    }
}

struct CompactWaveformBar: View {
    let amplitude: CGFloat
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 14

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 2, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

struct ProcessingWaveformView: View {
    private static let barCount = 5
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 4) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    ProcessingPill(
                        amplitude: amplitude(for: index, time: time),
                        opacity: opacity(for: index, time: time)
                    )
                }
            }
            .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phase(for index: Int, time: TimeInterval) -> Double {
        let cycle = 1.05
        let stagger = 0.11
        return ((time - Double(index) * stagger).truncatingRemainder(dividingBy: cycle)) / cycle
    }

    private func pulse(for index: Int, time: TimeInterval) -> CGFloat {
        let phase = phase(for: index, time: time)
        let wave = 0.5 + 0.5 * sin((phase * 2.0 * .pi) - (.pi / 2.0))
        return CGFloat(pow(wave, 1.9))
    }

    private func amplitude(for index: Int, time: TimeInterval) -> CGFloat {
        let centerDistance = abs(CGFloat(index) - Self.centerIndex) / Self.centerIndex
        let baseline = 0.18 + (1.0 - centerDistance) * 0.1
        return min(baseline + pulse(for: index, time: time) * 0.68, 1.0)
    }

    private func opacity(for index: Int, time: TimeInterval) -> CGFloat {
        0.42 + pulse(for: index, time: time) * 0.52
    }
}

private struct ProcessingPill: View {
    let amplitude: CGFloat
    let opacity: CGFloat

    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 18

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 4, height: minHeight + (maxHeight - minHeight) * amplitude)
            .opacity(opacity)
    }
}

struct ProcessingIndicatorView: View {
    @State private var showsExtendedSpinner = false
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            if showsExtendedSpinner {
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(rotation))
                    .frame(height: 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onAppear {
                        rotation = 0
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                ProcessingWaveformView()
                    .transition(.opacity)
            }
        }
        .task {
            showsExtendedSpinner = false
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsExtendedSpinner = true
                }
            } catch {}
        }
    }
}

/// Same hybrid waveform-then-spinner as `ProcessingIndicatorView`, sized to
/// fit the 18pt winged menu-bar overlay. Uses tighter pills and a smaller
/// spinner so the indicator stays inside the wing without the jolt to
/// oversized capsules that the full-size indicator produced.
struct CompactProcessingIndicatorView: View {
    @State private var showsExtendedSpinner = false
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            if showsExtendedSpinner {
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(rotation))
                    .frame(height: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onAppear {
                        rotation = 0
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
            } else {
                CompactProcessingWaveformView()
                    .transition(.opacity)
            }
        }
        .task {
            showsExtendedSpinner = false
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsExtendedSpinner = true
                }
            } catch {}
        }
    }
}

struct CompactProcessingWaveformView: View {
    private static let barCount = 5
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    CompactProcessingPill(
                        amplitude: amplitude(for: index, time: time),
                        opacity: opacity(for: index, time: time)
                    )
                }
            }
            .frame(height: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phase(for index: Int, time: TimeInterval) -> Double {
        let cycle = 1.05
        let stagger = 0.11
        return ((time - Double(index) * stagger).truncatingRemainder(dividingBy: cycle)) / cycle
    }

    private func pulse(for index: Int, time: TimeInterval) -> CGFloat {
        let phase = phase(for: index, time: time)
        let wave = 0.5 + 0.5 * sin((phase * 2.0 * .pi) - (.pi / 2.0))
        return CGFloat(pow(wave, 1.9))
    }

    private func amplitude(for index: Int, time: TimeInterval) -> CGFloat {
        let centerDistance = abs(CGFloat(index) - Self.centerIndex) / Self.centerIndex
        let baseline = 0.18 + (1.0 - centerDistance) * 0.1
        return min(baseline + pulse(for: index, time: time) * 0.68, 1.0)
    }

    private func opacity(for index: Int, time: TimeInterval) -> CGFloat {
        0.42 + pulse(for: index, time: time) * 0.52
    }
}

private struct CompactProcessingPill: View {
    let amplitude: CGFloat
    let opacity: CGFloat

    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 12

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: 2, height: minHeight + (maxHeight - minHeight) * amplitude)
            .opacity(opacity)
    }
}

struct InitializingDotsView: View {
    @State private var activeDot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(activeDot == index ? 0.9 : 0.25))
                    .frame(width: 4.5, height: 4.5)
                    .animation(.easeInOut(duration: 0.4), value: activeDot)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                DispatchQueue.main.async {
                    activeDot = (activeDot + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// Default floating recording card positioned above the Dock. It keeps a
/// stable footprint from shortcut acceptance through transcription so the UI
/// never jumps when the first preview words arrive.
private struct BottomListeningCardView: View {
    @ObservedObject var state: RecordingOverlayState
    let showsLiveTranscript: Bool
    let onStopButtonPressed: () -> Void
    let onCancelButtonPressed: () -> Void
    let onUpdateOverlayPressed: () -> Void

    @State private var isHovering = false

    private var isListening: Bool {
        state.phase == .recording
    }

    private var footerTitle: String {
        switch state.phase {
        case .initializing:
            return "Preparing microphone…"
        case .recording where state.recordingTriggerMode == .manual:
            return "Click to send"
        case .recording:
            return "Release to send"
        case .transcribing:
            return "Finishing…"
        case .feedback, .updateAvailable:
            return ""
        }
    }

    private var showsRecordingActions: Bool {
        state.phase == .recording
    }

    var body: some View {
        Group {
            if state.phase == .feedback, let message = state.errorMessage {
                ErrorOverlayView(message: message)
                    .padding(.horizontal, 18)
            } else if state.phase == .feedback {
                FailureIndicatorView()
            } else if state.phase == .updateAvailable {
                UpdateAvailableOverlayView(
                    version: state.updateVersion,
                    onPress: onUpdateOverlayPressed
                )
                    .padding(.horizontal, 18)
            } else {
                ZStack {
                    ZStack {
                        BottomCardDotGridView(
                            audioLevel: state.audioLevel,
                            isRecording: isListening
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        cardContent
                    }
                    .opacity(isHovering && showsRecordingActions ? 0.22 : 1)

                    if isHovering && showsRecordingActions {
                        recordingActions
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.16), value: state.phase)
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 35)

            centerContent
                .frame(height: 43)

            footer
                .frame(height: 34)
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Group {
                if let icon = state.targetApplicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(state.targetApplicationName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            if state.isCommandMode {
                CommandModeIndicator()
            }

            Spacer(minLength: 12)

            CompactOnSpeakBrand()
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var centerContent: some View {
        VStack(spacing: 1) {
            Color.clear
                .frame(
                    height: (showsLiveTranscript && !state.liveTranscript.isEmpty)
                        || state.phase == .transcribing
                        ? 14
                        : 28
                )
                .padding(.horizontal, 12)

            if showsLiveTranscript, !state.liveTranscript.isEmpty {
                CompactLiveTranscriptPreview(text: state.liveTranscript)
                    .frame(height: 28)
                    .transition(.opacity)
            } else if state.phase == .transcribing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finishing transcript…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                }
                .frame(height: 28)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsLiveTranscript)
    }

    private var footer: some View {
        HStack {
            Text(footerTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var recordingActions: some View {
        VStack(spacing: 0) {
            Button {
                isHovering = false
                onStopButtonPressed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish recording")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.24, green: 0.62, blue: 1.0))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .overlay(.white.opacity(0.08))

            Button {
                isHovering = false
                onCancelButtonPressed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("Cancel recording")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.24, blue: 0.27))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.96))
    }
}

private struct CompactOnSpeakBrand: View {
    var body: some View {
        HStack(spacing: 3) {
            StaticOnSpeakMark(markSize: 13)
            Text("OnSpeak")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.42))
        .fixedSize()
    }
}

/// A single, bounded drawing surface behind the floating-card content. It uses
/// the recorder's already-normalized display level and never owns timer state.
private struct BottomCardDotGridView: View {
    let audioLevel: Float
    let isRecording: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let columns = 24
    private static let rows = 8

    private var level: CGFloat {
        guard audioLevel.isFinite else { return 0 }
        return CGFloat(min(max(audioLevel, 0), 1))
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !isRecording || reduceMotion
            )
        ) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                drawGrid(
                    in: &context,
                    size: size,
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawGrid(
        in context: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let insetX: CGFloat = 12
        let insetY: CGFloat = 10
        let usableWidth = max(0, size.width - insetX * 2)
        let usableHeight = max(0, size.height - insetY * 2)
        guard usableWidth > 0, usableHeight > 0 else { return }

        let columnSpacing = usableWidth / CGFloat(Self.columns - 1)
        let rowSpacing = usableHeight / CGFloat(Self.rows - 1)

        func point(column: Int, row: Int) -> CGPoint {
            CGPoint(
                x: insetX + CGFloat(column) * columnSpacing,
                y: insetY + CGFloat(row) * rowSpacing
            )
        }

        func activation(column: Int, row: Int) -> CGFloat {
            guard isRecording, level > 0 else { return 0 }

            let x = CGFloat(column) / CGFloat(Self.columns - 1)
            let y = CGFloat(row) / CGFloat(Self.rows - 1)
            let travellingPhase = time * 3.0 - Double(x * 7.0 + y * 4.0)
            let ripple = CGFloat(0.5 + 0.5 * sin(travellingPhase))
            let centerBias = 1 - min(1, abs(y - 0.5) * 1.15)
            return level * (0.25 + 0.75 * ripple) * (0.62 + 0.38 * centerBias)
        }

        for row in 0..<Self.rows {
            for column in 0..<Self.columns {
                let current = point(column: column, row: row)
                let currentActivation = activation(column: column, row: row)

                if column + 1 < Self.columns {
                    let neighbourActivation = activation(column: column + 1, row: row)
                    var path = Path()
                    path.move(to: current)
                    path.addLine(to: point(column: column + 1, row: row))
                    let strength = max(currentActivation, neighbourActivation)
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.032 + strength * 0.075)),
                        lineWidth: 0.45 + strength * 0.18
                    )
                }

                if row + 1 < Self.rows {
                    let neighbourActivation = activation(column: column, row: row + 1)
                    var path = Path()
                    path.move(to: current)
                    path.addLine(to: point(column: column, row: row + 1))
                    let strength = max(currentActivation, neighbourActivation)
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.032 + strength * 0.075)),
                        lineWidth: 0.45 + strength * 0.18
                    )
                }

                let diameter = 1.8 + currentActivation * 1.7
                let dotRect = CGRect(
                    x: current.x - diameter / 2,
                    y: current.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(.white.opacity(0.08 + currentActivation * 0.19))
                )
            }
        }
    }
}

private struct CompactLiveTranscriptPreview: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .lineSpacing(1)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .contentTransition(.interpolate)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState
    let contentRowHeight: CGFloat
    let showsLiveTranscript: Bool
    let onStopButtonPressed: () -> Void
    let onUpdateOverlayPressed: () -> Void

    private let leadingAccessoryWidth: CGFloat = 24
    private let trailingAccessoryWidth: CGFloat = 32

    private var showsLiveRecordingContent: Bool {
        state.phase == .recording
    }

    private var showsStopButton: Bool {
        showsLiveRecordingContent && state.recordingTriggerMode == .manual
    }

    var body: some View {
        Group {
            if state.phase == .feedback, let message = state.errorMessage {
                ErrorOverlayView(message: message)
                    .padding(.horizontal, 12)
            } else if state.phase == .feedback {
                FailureIndicatorView()
                    .padding(.horizontal, 12)
            } else if state.phase == .updateAvailable {
                UpdateAvailableOverlayView(
                    version: state.updateVersion,
                    onPress: onUpdateOverlayPressed
                )
                    .padding(.horizontal, 12)
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        Group {
                            if state.phase == .initializing {
                                InitializingDotsView()
                                    .transition(.opacity)
                            } else if showsLiveRecordingContent {
                                Group {
                                    if showsLiveTranscript {
                                        OnSpeakOverlayBrand(
                                            audioLevel: state.audioLevel,
                                            isActive: state.phase == .recording
                                        )
                                    } else {
                                        WaveformView(
                                            audioLevel: state.audioLevel,
                                            showsActivityPulse: state.phase == .recording
                                        )
                                    }
                                }
                                .transition(.opacity)
                            } else {
                                ProcessingIndicatorView()
                                    .transition(.opacity)
                            }
                        }

                        HStack {
                            Group {
                                if state.isCommandMode {
                                    CommandModeIndicator()
                                        .transition(.opacity)
                                }
                            }
                            .frame(width: leadingAccessoryWidth, alignment: .center)
                            .frame(maxHeight: .infinity, alignment: .center)

                            Spacer(minLength: 0)

                            Group {
                                if showsStopButton {
                                    Button(action: onStopButtonPressed) {
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 14, height: 14)
                                            .background(Circle().fill(Color.red.opacity(0.92)))
                                    }
                                    .buttonStyle(.plain)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                            }
                            .frame(width: trailingAccessoryWidth, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: contentRowHeight)

                    if showsLiveTranscript {
                        LiveTranscriptStrip(text: state.liveTranscript)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.phase)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.recordingTriggerMode)
        .animation(.spring(response: 0.28, dampingFraction: 1.0), value: state.isCommandMode)
    }
}

/// Compact listening lockup for the expanded preview. The real app mark owns
/// the motion, so a separate waveform is unnecessary.
private struct OnSpeakOverlayBrand: View {
    let audioLevel: Float
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            StaticOnSpeakMark(markSize: 15)

            Text("OnSpeak")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OnSpeak")
    }
}

/// The exact OnSpeak template mark, kept still and optically matched to the
/// adjacent wordmark instead of acting as a second activity indicator.
private struct StaticOnSpeakMark: View {
    let markSize: CGFloat

    var body: some View {
        Image(nsImage: OnSpeakMenuBarIcon.templateImage)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: markSize, height: markSize)
            .foregroundStyle(.white)
            .accessibilityHidden(true)
    }
}

// MARK: - Transcribing Indicator

struct CommandModeIndicator: View {
    var body: some View {
        Image(systemName: "pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 16, height: 16, alignment: .center)
    }
}

struct FailureIndicatorView: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.red.opacity(0.92)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// In-pill error toast. Red exclamation icon plus the message text,
/// rendered inside the standard menu-bar pill. Sized by the manager's
/// `overlayWidth` based on message length.
struct ErrorOverlayView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.92))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct UpdateAvailableOverlayView: View {
    let version: String
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text(version.isEmpty ? "Update Available" : "OnSpeak \(version) Available")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }
}
