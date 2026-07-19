import Foundation

enum DictionaryTermLearnerTests {
    static func run() {
        testAcceptsAcronym()
        testAcceptsInternalCapital()
        testAcceptsDigitBearingTerm()
        testAcceptsTechnicalSeparators()
        testAcceptsMidSentenceCapitalizedName()
        testRejectsCommonStopSetWords()
        testRejectsSentenceInitialOrdinaryCapitalizedWord()
        testRejectsEmailAddress()
        testRejectsURL()
        testRejectsHttpPrefixedTermEvenWhenShapeQualifies()
        testCanonicalFoldingRejectsAllCapsStopWords()
        testCandidatesPreserveOrderAndDuplicates()
        testTrailingPeriodBypassesStopSetFilterForMidSentenceStopWord()
    }

    // MARK: - accepts: acronyms

    private static func testAcceptsAcronym() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "API access requires a token today."),
            ["API"]
        )
    }

    // MARK: - accepts: internal capitals

    private static func testAcceptsInternalCapital() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "I switched to macOS recently for work."),
            ["macOS"]
        )
    }

    // MARK: - accepts: digit-bearing terms

    private static func testAcceptsDigitBearingTerm() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "We are moving to web3 platforms soon."),
            ["web3"]
        )
    }

    // MARK: - accepts: technical separators (-, _, +)

    private static func testAcceptsTechnicalSeparators() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "We need a front-end engineer soon."),
            ["front-end"],
            "hyphen separator"
        )
        expectEqual(
            DictionaryTermLearner.candidates(from: "Use snake_case for variables please."),
            ["snake_case"],
            "underscore separator"
        )
        expectEqual(
            DictionaryTermLearner.candidates(from: "I write C++ for work."),
            ["C++"],
            "plus separator"
        )
    }

    // MARK: - accepts: mid-sentence capitalized names

    private static func testAcceptsMidSentenceCapitalizedName() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "I met Rushat yesterday for coffee."),
            ["Rushat"]
        )
    }

    // MARK: - rejects: common stop-set words

    private static func testRejectsCommonStopSetWords() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "Please send me the file when you have it"),
            []
        )
    }

    // MARK: - rejects: sentence-initial capitals that are ordinary words

    private static func testRejectsSentenceInitialOrdinaryCapitalizedWord() {
        // "Yesterday" is sentence-initial and an ordinary word (not in the stop
        // set, no acronym/technical shape), so it must be excluded, while the
        // mid-sentence name "Rushat" in the same sentence is still accepted.
        expectEqual(
            DictionaryTermLearner.candidates(from: "Yesterday I met Rushat for coffee."),
            ["Rushat"]
        )
    }

    // MARK: - rejects: email addresses

    private static func testRejectsEmailAddress() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "Email me at rushat.dev@example.com today."),
            []
        )
    }

    // MARK: - rejects: URLs

    private static func testRejectsURL() {
        expectEqual(
            DictionaryTermLearner.candidates(from: "Visit http://example.com for docs now."),
            []
        )
    }

    private static func testRejectsHttpPrefixedTermEvenWhenShapeQualifies() {
        // "HTTP2" is acronym-shaped (all-caps letters plus a digit) and would
        // otherwise qualify as a candidate on shape alone; the explicit
        // http-prefix guard must still exclude it.
        expectEqual(
            DictionaryTermLearner.candidates(from: "Visit HTTP2 protocol docs now."),
            []
        )
    }

    // MARK: - canonical folding on near-duplicates

    private static func testCanonicalFoldingRejectsAllCapsStopWords() {
        // "THE" is acronym-shaped (all uppercase letters, no lowercase), which
        // would otherwise qualify it as a candidate; case/diacritic folding
        // against the stop set must still catch it as "the".
        expectEqual(
            DictionaryTermLearner.candidates(from: "Please buy THE gadget."),
            []
        )

        // "AND" is likewise acronym-shaped but folds to the stop-set word
        // "and"; the legitimately name-shaped "Sam" in the same sentence is
        // still accepted, showing the folding rejects only the stop word.
        expectEqual(
            DictionaryTermLearner.candidates(from: "Call Sam AND go."),
            ["Sam"]
        )
    }

    // MARK: - order and duplicates

    private static func testCandidatesPreserveOrderAndDuplicates() {
        // The doc comment on candidates(from:) promises order and duplicates
        // are preserved; DictionaryStore.observe collapses repeats per call,
        // not the learner.
        expectEqual(
            DictionaryTermLearner.candidates(from: "I called Rushat and later texted Rushat too."),
            ["Rushat", "Rushat"]
        )
    }

    // MARK: - surprising behavior: trailing sentence punctuation

    private static func testTrailingPeriodBypassesStopSetFilterForMidSentenceStopWord() {
        // Regression: the extraction regex's continuation class includes '.'
        // (so identifiers like "file.txt" survive), which used to glue the
        // sentence-final period onto the last word. A capitalized stop word at
        // sentence end then dodged the stop set ("This." != "this") and was
        // learned verbatim with its period. Trailing dots are now stripped
        // before filtering, so the stop set rejects it entirely.
        expectEqual(
            DictionaryTermLearner.candidates(from: "I like her more than This."),
            []
        )
        // And a legitimate sentence-final name is learned without its period.
        expectEqual(
            DictionaryTermLearner.candidates(from: "I spoke with Nadia."),
            ["Nadia"]
        )
        // Internal dots in qualifying technical tokens still survive — only
        // TRAILING dots are stripped. (A dot alone is not a qualifying shape;
        // this token qualifies via its internal capital.)
        expectEqual(
            DictionaryTermLearner.candidates(from: "open the file AppDelegate.swift please"),
            ["AppDelegate.swift"]
        )
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
