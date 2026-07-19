import Foundation

enum LiveTranscriptComposerTests {
    static func run() {
        testFinalsOnlyMatchLegacyAccumulation()
        testVolatileResultsReplaceRatherThanAppend()
        testFinalResultAppendsAndClearsVolatileText()
        testCommittedTextExcludesVolatileTextAcrossInterleavings()
        testEmptyAndWhitespaceBehaviorMatchesCommitBoundary()
    }

    private static func testFinalsOnlyMatchLegacyAccumulation() {
        var first: AttributedString = " Hello"
        first.link = URL(string: "https://example.com/first")
        var second: AttributedString = " world"
        second.link = URL(string: "https://example.com/second")
        let results: [AttributedString] = [
            first,
            second,
            "! ",
        ]
        var legacyTranscript: AttributedString = ""
        var composer = LiveTranscriptComposer()

        for result in results {
            legacyTranscript += result
            composer.ingest(text: result, isFinal: true)
        }

        expectEqual(composer.finalizedText, legacyTranscript)
        expectEqual(composer.volatileText, AttributedString(""))
        expectEqual(composer.previewText, String(legacyTranscript.characters))
        expectEqual(composer.committedText, String(legacyTranscript.characters))
    }

    private static func testVolatileResultsReplaceRatherThanAppend() {
        var composer = LiveTranscriptComposer()

        composer.ingest(text: "recogn", isFinal: false)
        expectEqual(composer.previewText, "recogn")
        expectEqual(composer.committedText, "")

        composer.ingest(text: "recognized phrase", isFinal: false)
        expectEqual(composer.volatileText, AttributedString("recognized phrase"))
        expectEqual(composer.previewText, "recognized phrase")
        expectEqual(composer.committedText, "")
    }

    private static func testFinalResultAppendsAndClearsVolatileText() {
        var composer = LiveTranscriptComposer()
        composer.ingest(text: "provisional", isFinal: false)
        composer.ingest(text: "Final phrase. ", isFinal: true)

        expectEqual(composer.finalizedText, AttributedString("Final phrase. "))
        expectEqual(composer.volatileText, AttributedString(""))
        expectEqual(composer.previewText, "Final phrase. ")
        expectEqual(composer.committedText, "Final phrase. ")

        composer.ingest(text: "Second phrase.", isFinal: true)
        expectEqual(composer.finalizedText, AttributedString("Final phrase. Second phrase."))
        expectEqual(composer.previewText, "Final phrase. Second phrase.")
        expectEqual(composer.committedText, "Final phrase. Second phrase.")
    }

    private static func testCommittedTextExcludesVolatileTextAcrossInterleavings() {
        // Enumerate every final/volatile ordering through six results and
        // verify every prefix, covering all state transitions and repeated
        // transitions rather than only a few hand-picked examples.
        for length in 0...6 {
            for pattern in 0..<(1 << length) {
                var composer = LiveTranscriptComposer()
                var expectedFinalized = ""
                var expectedVolatile = ""

                for index in 0..<length {
                    let isFinal = pattern & (1 << index) != 0
                    let marker = isFinal ? "F\(index)|" : "V\(index)|"
                    composer.ingest(text: AttributedString(marker), isFinal: isFinal)

                    if isFinal {
                        expectedFinalized += marker
                        expectedVolatile = ""
                    } else {
                        expectedVolatile = marker
                    }

                    let context = "length=\(length), pattern=\(pattern), prefix=\(index)"
                    expectEqual(composer.committedText, expectedFinalized, context)
                    expectEqual(composer.previewText, expectedFinalized + expectedVolatile, context)

                    for volatileIndex in 0...index {
                        expect(
                            !composer.committedText.contains("V\(volatileIndex)|"),
                            "volatile text leaked into committed text (\(context))"
                        )
                    }
                }
            }
        }
    }

    private static func testEmptyAndWhitespaceBehaviorMatchesCommitBoundary() {
        var composer = LiveTranscriptComposer()
        expectEqual(composer.previewText, "")
        expectEqual(composer.committedText, "")

        composer.ingest(text: "  provisional\n", isFinal: false)
        expectEqual(composer.previewText, "  provisional\n")
        expectEqual(composer.committedText, "")

        // Even an empty final supersedes the current provisional run.
        composer.ingest(text: "", isFinal: true)
        expectEqual(composer.previewText, "")
        expectEqual(composer.committedText, "")

        // The current service accumulates result text byte-for-byte, then
        // trims once at the commit boundary. The composer preserves that split.
        composer.ingest(text: " \n\t", isFinal: true)
        composer.ingest(text: "  hello world  ", isFinal: true)
        composer.ingest(text: "\n", isFinal: true)
        expectEqual(composer.committedText, " \n\t  hello world  \n")
        expectEqual(
            composer.committedText.trimmingCharacters(in: .whitespacesAndNewlines),
            "hello world"
        )

        var whitespaceOnly = LiveTranscriptComposer()
        whitespaceOnly.ingest(text: " \t\n ", isFinal: true)
        expectEqual(whitespaceOnly.committedText, " \t\n ")
        expectEqual(
            whitespaceOnly.committedText.trimmingCharacters(in: .whitespacesAndNewlines),
            ""
        )
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
