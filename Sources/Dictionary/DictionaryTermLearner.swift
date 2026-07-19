import Foundation

// MARK: - DictionaryTermLearner

/// Extracts the handful of unusual terms in a finished transcript that are
/// worth teaching the personal dictionary — names, acronyms, product words,
/// and technical tokens the recognizer keeps getting wrong.
///
/// This type is deliberately dependency-free — it imports only `Foundation`,
/// touches no `UserDefaults` or OS state, and does no I/O — so it can be
/// exercised directly by the `make test` runner alongside `DynamicCleanupGuard`
/// and `TranscriptTidier`. It only proposes candidates; `DictionaryStore`
/// decides what is remembered, and a candidate still needs three independent
/// observations before it activates. Because a single mistaken candidate costs
/// three separate dictations to matter, extraction favors **precision over
/// recall**: it would rather miss a real term than pollute the dictionary with
/// ordinary words.
enum DictionaryTermLearner {

    // MARK: Stop set

    /// Common English words that must never be treated as candidates even when
    /// they slip past the shape heuristics (e.g. a sentence-initial "The"). The
    /// list is intentionally small and high-frequency; anything technical or
    /// name-like is expected to survive.
    static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for",
        "from", "had", "has", "have", "he", "her", "here", "his", "how", "i", "if",
        "in", "is", "it", "its", "just", "me", "my", "no", "not", "of", "on", "or",
        "our", "please", "she", "so", "that", "the", "their", "them", "then", "there",
        "they", "this", "to", "up", "us", "was", "we", "were", "what", "when", "where",
        "which", "who", "will", "with", "would", "yes", "you", "your"
    ]

    // MARK: Extraction

    /// Finds conservative names and technical tokens worth observing in
    /// `transcript`. A returned token qualifies only if it is an acronym, has an
    /// internal capital, contains a digit, has a technical separator
    /// (`-`, `_`, `+`), or is a mid-sentence capitalized name — and is not a
    /// common English word, an email address, or a URL. Order and duplicates are
    /// preserved; `DictionaryStore.observe(candidateTerms:)` collapses repeats
    /// per dictation.
    static func candidates(from transcript: String) -> [String] {
        // A token starts with a letter or digit and runs up to 64 characters of
        // letters, digits, apostrophes, and the separators used by identifiers.
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’._+-]{1,63}"#
        ) else { return [] }

        let nsTranscript = transcript as NSString
        let matches = regex.matches(
            in: transcript,
            range: NSRange(location: 0, length: nsTranscript.length)
        )

        return matches.compactMap { match in
            var term = nsTranscript.substring(with: match.range)
            // The token class includes "." so identifiers like "file.txt"
            // survive, but that also glues sentence-final punctuation onto the
            // last word. Strip trailing dots so a name at sentence end is
            // learned as "Nadia", not "Nadia.", and a capitalized stop word
            // there ("This.") still hits the stop set below.
            while term.hasSuffix(".") { term.removeLast() }
            guard !term.isEmpty else { return nil }
            let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !commonWords.contains(folded),
                  !term.contains("@"),
                  !term.lowercased().hasPrefix("http") else { return nil }

            let letters = term.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            guard !letters.isEmpty else { return nil }
            let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            let lowercaseCount = letters.filter { CharacterSet.lowercaseLetters.contains($0) }.count
            let hasNumber = term.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            let hasTechnicalSeparator = term.contains("-") || term.contains("_") || term.contains("+")
            let isAcronym = uppercaseCount >= 2 && lowercaseCount == 0
            let hasInternalCapital = term.dropFirst().unicodeScalars.contains {
                CharacterSet.uppercaseLetters.contains($0)
            }

            // A capitalized word away from a sentence boundary is likely a
            // proper name. Sentence-initial capitalization alone is too weak to
            // trust, so it is excluded from the name heuristic.
            let prefix = nsTranscript.substring(to: match.range.location)
            let prior = prefix.trimmingCharacters(in: .whitespacesAndNewlines).last
            let isSentenceInitial = prior == nil || ".!?".contains(prior!)
            let isMidSentenceName = uppercaseCount >= 1 && !isSentenceInitial

            guard isAcronym || hasInternalCapital || hasNumber || hasTechnicalSeparator || isMidSentenceName else {
                return nil
            }
            return term
        }
    }
}
