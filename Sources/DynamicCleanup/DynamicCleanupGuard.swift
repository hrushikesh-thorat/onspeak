import Foundation

// MARK: - DynamicCleanupGuard

/// Pure sanitizer and validator for on-device dynamic-cleanup output.
///
/// This type is deliberately dependency-free — it imports only `Foundation`,
/// touches no `FoundationModels` symbol, and performs no OS I/O — so it can be
/// exercised directly by the `make test` runner alongside `TranscriptTidier`.
/// The on-device model is markedly weaker than the retired cloud models, so
/// its output is never trusted blindly: `AppleFoundationModelsPostProcessor`
/// sanitizes every response through ``sanitize(_:)`` and then gates it through
/// ``validate(_:source:)`` before it is allowed to replace the deterministic
/// tidier's text. Any rejection makes the caller fall back to the tidied
/// transcript, so the user always gets at least the 0.2.0 result.
enum DynamicCleanupGuard {

    // MARK: Rejection reasons

    /// Why a candidate cleanup output was rejected. The post-processor maps
    /// each case onto a `DynamicCleanupError` so the failure reason reaches the
    /// Run Log; all of them resolve to the same user-invisible fallback.
    enum Rejection: Equatable {
        /// Output was empty after sanitizing (input was non-empty).
        case empty
        /// Output opened with an assistant-style preamble ("Here is…",
        /// "As an AI…"), meaning the model answered instead of cleaning.
        case assistantPrefix
        /// Output blew past the length bound — the model expanded or
        /// hallucinated rather than making minimum edits.
        case exceededLengthBound(limit: Int)
    }

    // MARK: Assistant-style prefixes

    /// Lowercased prefixes that betray a conversational/assistant reply rather
    /// than a cleaned transcript. Matched against the lowercased output.
    static let rejectedPrefixes: [String] = [
        "here is", "here's", "certainly", "sure,", "i'm sorry", "i am sorry",
        "as an ai", "i can't", "i cannot"
    ]

    // MARK: Sanitizing

    /// Strips wrapper artifacts the model sometimes adds around the useful
    /// text: `<response>…</response>` XML tags and a single outer pair of
    /// quotation marks. The two wrappers can nest in either order
    /// (`"<response>…</response>"` as well as `<response>"…"</response>`),
    /// so stripping repeats until a full pass changes nothing.
    ///
    /// Quote stripping is conservative: a pair is removed only when the text
    /// begins and ends with a matching quote *and* the interior holds no other
    /// instance of that quote, so ordinary quoted phrasing such as
    /// `"a" and "b"` is left untouched.
    static func sanitize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while !value.isEmpty {
            let before = value
            value = strippingResponseTags(value)
            value = strippingOuterQuotes(value)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == before { break }
        }
        return value
    }

    /// Removes surrounding `<response> … </response>` tags. Loops so a doubly
    /// wrapped payload collapses fully; stops as soon as a pass changes nothing.
    private static func strippingResponseTags(_ input: String) -> String {
        var value = input
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        while !value.isEmpty {
            let before = value
            if let opening = value.range(of: #"^<response\s*>\s*"#, options: options) {
                value.removeSubrange(opening)
            }
            if let closing = value.range(of: #"\s*</response\s*>$"#, options: options) {
                value.removeSubrange(closing)
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == before { break }
        }
        return value
    }

    /// Matched outer quote pairs to unwrap. Straight and smart double quotes,
    /// straight and smart single quotes, and backticks.
    private static let outerQuotePairs: [(open: Character, close: Character)] = [
        ("\"", "\""),
        ("\u{201C}", "\u{201D}"),
        ("'", "'"),
        ("\u{2018}", "\u{2019}"),
        ("`", "`"),
    ]

    private static func strippingOuterQuotes(_ input: String) -> String {
        guard input.count >= 2, let first = input.first, let last = input.last else {
            return input
        }
        for pair in outerQuotePairs where first == pair.open && last == pair.close {
            let inner = input.dropFirst().dropLast()
            // Only unwrap when the interior does not itself contain either
            // quote character, so text that legitimately opens and closes with
            // quotes (e.g. `"a" and "b"`) is preserved.
            if !inner.contains(pair.open) && !inner.contains(pair.close) {
                return String(inner)
            }
        }
        return input
    }

    // MARK: Validation

    /// Upper bound on output length relative to the source transcript.
    /// `max(source × 2, source + 200)` — the `+ 200` floor keeps short
    /// dictations (where doubling is a tiny absolute budget) from tripping the
    /// bound on legitimate punctuation and casing edits.
    static func lengthLimit(forSource source: String) -> Int {
        let sourceCount = max(source.count, 1)
        return max(sourceCount * 2, sourceCount + 200)
    }

    /// Validates already-sanitized cleanup output against its source
    /// transcript. Returns the first failing check, or `nil` when the output
    /// is acceptable.
    static func validate(_ output: String, source: String) -> Rejection? {
        guard !output.isEmpty else { return .empty }
        // Fold the curly apostrophe models routinely emit ("I’m sorry") onto
        // the straight form used by `rejectedPrefixes` before matching.
        let lower = output.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        if rejectedPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return .assistantPrefix
        }
        let limit = lengthLimit(forSource: source)
        if output.count > limit {
            return .exceededLengthBound(limit: limit)
        }
        return nil
    }
}
