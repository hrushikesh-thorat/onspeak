import Foundation

enum LiveTranscriptSessionSupportTests {
    static func run() {
        testElapsedMillisecondsUsesInjectedUptime()
        testElapsedMillisecondsClampsNegativeIntervals()
        testBeginningNewSessionReplacesActiveSession()
        testMatchingAndStaleInvalidation()
        testAcceptanceAcrossSessionLifetime()
        testSelectionSnapshotPolicyTruthTable()
        testStreamingStartupPlanPreservesPreviewOffBehavior()
        testStreamingStartupPlanRetriesAccurateOnlyAfterCombinedAttempt()
        testLiveTranscriptDeliveryLatchCoalescesNewestSessionPayload()
        testLiveTranscriptDeliveryLatchCancellationDropsQueuedPayload()
    }

    private static func testElapsedMillisecondsUsesInjectedUptime() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let context = LiveTranscriptSessionContext(id: id, startedAtUptime: 100.25)

        expectEqual(context.id, id)
        expectEqual(context.startedAtUptime, 100.25)
        expectEqual(context.elapsedMilliseconds(now: 100.25), 0)
        expectEqual(context.elapsedMilliseconds(now: 101.50), 1_250)
        expectEqual(context.elapsedMilliseconds(now: 101.5009), 1_250)
    }

    private static func testElapsedMillisecondsClampsNegativeIntervals() {
        let context = LiveTranscriptSessionContext(startedAtUptime: 42)

        expectEqual(context.elapsedMilliseconds(now: 41), 0)
        expectEqual(context.elapsedMilliseconds(now: 42), 0)
    }

    private static func testBeginningNewSessionReplacesActiveSession() {
        let first = context(idSuffix: 1)
        let second = context(idSuffix: 2)
        var gate = LiveTranscriptSessionGate()

        expectEqual(gate.activeContext, nil)
        expectEqual(gate.activeSessionID, nil)

        gate.begin(first)
        expectEqual(gate.activeContext, first)
        expectEqual(gate.activeSessionID, first.id)

        gate.begin(second)
        expectEqual(gate.activeContext, second)
        expectEqual(gate.activeSessionID, second.id)
        expect(!gate.accepts(sessionID: first.id), "replaced session was still accepted")
        expect(gate.accepts(sessionID: second.id), "replacement session was rejected")
    }

    private static func testMatchingAndStaleInvalidation() {
        let stale = context(idSuffix: 3)
        let current = context(idSuffix: 4)
        var gate = LiveTranscriptSessionGate()
        gate.begin(current)

        expect(!gate.invalidate(matching: stale.id), "stale ID reported invalidation")
        expectEqual(gate.activeContext, current)

        expect(gate.invalidate(matching: current.id), "current ID was not invalidated")
        expectEqual(gate.activeContext, nil)
        expectEqual(gate.activeSessionID, nil)
    }

    private static func testAcceptanceAcrossSessionLifetime() {
        let active = context(idSuffix: 5)
        let unrelated = context(idSuffix: 6)
        var gate = LiveTranscriptSessionGate()

        gate.begin(active)
        // An update may arrive before the overlay window has been constructed.
        expect(gate.accepts(sessionID: active.id), "early active update was rejected")
        expect(!gate.accepts(sessionID: unrelated.id), "unrelated update was accepted")

        // The same ID remains valid for ordinary in-session updates.
        expect(gate.accepts(sessionID: active.id), "current update was rejected")

        gate.invalidate()
        expect(!gate.accepts(sessionID: active.id), "dismissed session was revived")
        expectEqual(gate.activeContext, nil)
    }

    private static func testSelectionSnapshotPolicyTruthTable() {
        for editModeEnabled in [false, true] {
            for usesAutomaticStyle in [false, true] {
                for manualCommandRequested in [false, true] {
                    let expected = editModeEnabled
                        && (usesAutomaticStyle || manualCommandRequested)
                    let actual = SelectionSnapshotPolicy.requiresSnapshot(
                        editModeEnabled: editModeEnabled,
                        usesAutomaticStyle: usesAutomaticStyle,
                        manualCommandRequested: manualCommandRequested
                    )
                    let context = "editModeEnabled=\(editModeEnabled), "
                        + "usesAutomaticStyle=\(usesAutomaticStyle), "
                        + "manualCommandRequested=\(manualCommandRequested)"
                    expectEqual(actual, expected, context)
                }
            }
        }
    }

    private static func testStreamingStartupPlanPreservesPreviewOffBehavior() {
        expectEqual(
            SpeechAnalyzerStreamingStartupPlan.attempts(previewEnabled: false),
            [.accurateOnly]
        )
    }

    private static func testStreamingStartupPlanRetriesAccurateOnlyAfterCombinedAttempt() {
        expectEqual(
            SpeechAnalyzerStreamingStartupPlan.attempts(previewEnabled: true),
            [.accurateAndPreview, .accurateOnly]
        )
    }

    private static func testLiveTranscriptDeliveryLatchCoalescesNewestSessionPayload() {
        let firstID = context(idSuffix: 7).id
        let replacementID = context(idSuffix: 8).id
        var latch = LiveTranscriptDeliveryLatch()

        expect(latch.enqueue(sessionID: firstID, text: "first"), "first update did not schedule delivery")
        expect(
            !latch.enqueue(sessionID: replacementID, text: "replacement"),
            "replacement update scheduled a duplicate delivery"
        )

        let delivery = latch.take()
        expectEqual(delivery?.sessionID, replacementID)
        expectEqual(delivery?.text, "replacement")
        expectEqual(latch.pendingSessionID, nil)
        expectEqual(latch.pendingText, nil)
        expect(!latch.isDeliveryScheduled, "latch stayed closed after delivery")
    }

    private static func testLiveTranscriptDeliveryLatchCancellationDropsQueuedPayload() {
        let sessionID = context(idSuffix: 9).id
        var latch = LiveTranscriptDeliveryLatch()
        expect(latch.enqueue(sessionID: sessionID, text: "queued"), "update did not schedule delivery")

        latch.cancel()

        expectEqual(latch.take()?.sessionID, nil)
        expectEqual(latch.pendingSessionID, nil)
        expectEqual(latch.pendingText, nil)
        expect(!latch.isDeliveryScheduled, "cancelled latch remained scheduled")
    }

    private static func context(idSuffix: UInt8) -> LiveTranscriptSessionContext {
        let uuid = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, idSuffix
        ))
        return LiveTranscriptSessionContext(id: uuid, startedAtUptime: TimeInterval(idSuffix))
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ context: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if actual != expected {
            let suffix = context.isEmpty ? "" : " (\(context))"
            fatalError(
                "\(file):\(line): expected \(String(describing: expected)), "
                    + "got \(String(describing: actual))\(suffix)"
            )
        }
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
