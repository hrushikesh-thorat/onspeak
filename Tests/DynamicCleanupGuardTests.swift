import Foundation

enum DynamicCleanupGuardTests {
    static func run() {
        testSanitizeResponseTagStripping()
        testSanitizeQuoteWrappedTags()
        testSanitizeOuterQuoteStripping()
        testSanitizeConservativeQuoteRule()
        testSanitizeWhitespaceTrimming()
        testSanitizeEmptyInput()
        testValidateEmptyOutput()
        testValidateAssistantPrefixRejection()
        testValidateCurlyApostrophePrefixRejection()
        testValidateNonPrefixOccurrencePasses()
        testValidateLengthBoundMultiplyDominant()
        testValidateShortSourceFloorGoverns()
        testValidateEmptySourceUsesOneCharFloor()
        testValidateLegitimateReworkingPasses()
        testSanitizeThenValidateHappyPath()
    }

    // MARK: - sanitize: <response> tag stripping

    private static func testSanitizeResponseTagStripping() {
        expectEqual(DynamicCleanupGuard.sanitize("<response>Hello world</response>"), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("<RESPONSE>Hello world</RESPONSE>"), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("<ReSpOnSe>Hello world</rEsPoNsE>"), "Hello world")
        expectEqual(
            DynamicCleanupGuard.sanitize("<response><response>Hello world</response></response>"),
            "Hello world"
        )
        expectEqual(
            DynamicCleanupGuard.sanitize("<response>   Hello there   </response>"),
            "Hello there"
        )
        expectEqual(
            DynamicCleanupGuard.sanitize("<response  >  Hello  </response  >"),
            "Hello"
        )
        // Only the opening tag matches here; the implementation strips each
        // side independently, so an unmatched closing tag is left as-is.
        expectEqual(DynamicCleanupGuard.sanitize("<response>Hello world"), "Hello world")
    }

    private static func testSanitizeQuoteWrappedTags() {
        // Wrappers can nest in either order; both must strip fully.
        expectEqual(DynamicCleanupGuard.sanitize("\"<response>Hello world</response>\""), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("<response>\"Hello world\"</response>"), "Hello world")
    }

    // MARK: - sanitize: outer-quote stripping

    private static func testSanitizeOuterQuoteStripping() {
        expectEqual(DynamicCleanupGuard.sanitize("\"Hello world\""), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("\u{201C}Hello world\u{201D}"), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("'Hello world'"), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("\u{2018}Hello world\u{2019}"), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("`Hello world`"), "Hello world")
    }

    private static func testSanitizeConservativeQuoteRule() {
        // Two separate quoted spans rather than one enclosing pair: the
        // outer quotes carry meaning and must be preserved.
        let unchanged = [
            "\"a\" and \"b\"",
            "'a' and 'b'",
            // Interior repeats the same quote character used to open/close.
            "\"she said \"hi\" then left\"",
        ]
        for input in unchanged {
            expectEqual(DynamicCleanupGuard.sanitize(input), input, "conservative quote rule for: \(input)")
        }
    }

    private static func testSanitizeWhitespaceTrimming() {
        expectEqual(DynamicCleanupGuard.sanitize("   Hello world   "), "Hello world")
        expectEqual(DynamicCleanupGuard.sanitize("\n\tHello world\n"), "Hello world")
    }

    private static func testSanitizeEmptyInput() {
        expectEqual(DynamicCleanupGuard.sanitize(""), "")
        expectEqual(DynamicCleanupGuard.sanitize("   "), "")
    }

    // MARK: - validate: empty output

    private static func testValidateEmptyOutput() {
        expectEqual(DynamicCleanupGuard.validate("", source: "Hello world"), .empty)
    }

    // MARK: - validate: assistant-style prefixes

    private static func testValidateAssistantPrefixRejection() {
        for prefix in DynamicCleanupGuard.rejectedPrefixes {
            let output = prefix + " the cleaned transcript follows."
            expectEqual(
                DynamicCleanupGuard.validate(output, source: "short source"),
                .assistantPrefix,
                "expected rejection for prefix: \(prefix)"
            )

            let shouted = output.uppercased()
            expectEqual(
                DynamicCleanupGuard.validate(shouted, source: "short source"),
                .assistantPrefix,
                "expected case-insensitive rejection for prefix: \(prefix)"
            )
        }
    }

    private static func testValidateCurlyApostrophePrefixRejection() {
        // Models routinely emit curly apostrophes; the straight-apostrophe
        // prefix list must still catch them.
        expectEqual(
            DynamicCleanupGuard.validate("I\u{2019}m sorry, I can\u{2019}t help with that.", source: "short source"),
            .assistantPrefix
        )
        expectEqual(
            DynamicCleanupGuard.validate("I can\u{2019}t clean this transcript.", source: "short source"),
            .assistantPrefix
        )
    }

    private static func testValidateNonPrefixOccurrencePasses() {
        // "certainly" and "here is" both appear, but not as the leading
        // phrase, so this should not be treated as an assistant preamble.
        let source = "I certainly agree this is fine and here is why."
        let output = source
        expectEqual(DynamicCleanupGuard.validate(output, source: source), nil)
    }

    // MARK: - validate: length bound

    private static func testValidateLengthBoundMultiplyDominant() {
        let source = String(repeating: "s", count: 300)
        let limit = DynamicCleanupGuard.lengthLimit(forSource: source)
        expectEqual(limit, 600, "doubling should dominate for a long source")

        let atLimit = String(repeating: "o", count: limit)
        expectEqual(DynamicCleanupGuard.validate(atLimit, source: source), nil)

        let overLimit = String(repeating: "o", count: limit + 1)
        expectEqual(
            DynamicCleanupGuard.validate(overLimit, source: source),
            .exceededLengthBound(limit: limit)
        )
    }

    private static func testValidateShortSourceFloorGoverns() {
        let source = String(repeating: "s", count: 10)
        let limit = DynamicCleanupGuard.lengthLimit(forSource: source)
        expectEqual(limit, 210, "the +200 floor should dominate for a short source")

        let atLimit = String(repeating: "o", count: limit)
        expectEqual(DynamicCleanupGuard.validate(atLimit, source: source), nil)

        let overLimit = String(repeating: "o", count: limit + 1)
        expectEqual(
            DynamicCleanupGuard.validate(overLimit, source: source),
            .exceededLengthBound(limit: limit)
        )
    }

    private static func testValidateEmptySourceUsesOneCharFloor() {
        let limit = DynamicCleanupGuard.lengthLimit(forSource: "")
        expectEqual(limit, 201, "an empty source should be floored to a 1-char source count")

        let atLimit = String(repeating: "o", count: limit)
        expectEqual(DynamicCleanupGuard.validate(atLimit, source: ""), nil)

        let overLimit = String(repeating: "o", count: limit + 1)
        expectEqual(
            DynamicCleanupGuard.validate(overLimit, source: ""),
            .exceededLengthBound(limit: limit)
        )
    }

    private static func testValidateLegitimateReworkingPasses() {
        let source = "so um I think we should uh ship it today no wait tomorrow"
        let output = "I think we should ship it tomorrow."
        expectEqual(DynamicCleanupGuard.validate(output, source: source), nil)
    }

    // MARK: - combined sanitize -> validate

    private static func testSanitizeThenValidateHappyPath() {
        let raw = "  <response>\n\"Hey Dana, let's meet Wednesday instead of Thursday.\"\n</response>  "
        let sanitized = DynamicCleanupGuard.sanitize(raw)
        expectEqual(sanitized, "Hey Dana, let's meet Wednesday instead of Thursday.")

        let source = "hey dana lets meet thursday no actually wednesday"
        expectEqual(DynamicCleanupGuard.validate(sanitized, source: source), nil)
    }

    // MARK: - helpers

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if actual != expected {
            let context = message.isEmpty ? "" : " (\(message))"
            fatalError("\(file):\(line): expected \(String(describing: expected)), got \(String(describing: actual))\(context)")
        }
    }
}
