import Foundation

enum DictionaryStoreTests {
    static func run() {
        testThresholdActivatesAtExactlyThreeObservations()
        testSuggestionCapEvictsWeakestSuggestion()
        testLearnedCapBlocksNewCandidatesWhenNoSuggestionCanBeEvicted()
        testRejectedStaysRejected()
        testMigrationIsIdempotentAndRespectsPersistedFlag()
        testImportPlainTermsSkipsCorrectionsAndComments()
        testImportPlainTermsCommaInsideCorrectionReplacementDoesNotLeak()
        testAddManualPromotesExistingLearnedEntryAndDedupsCaseAndDiacriticInsensitively()
        testAddManualRejectsEmptyTerm()
        testActiveTermsOrderingAndDisabledExclusion()
    }

    // MARK: - learning threshold

    private static func testThresholdActivatesAtExactlyThreeObservations() {
        let (defaults, suite) = makeDefaults("threshold")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        store.observe(candidateTerms: ["Rushat"])
        store.observe(candidateTerms: ["Rushat"])
        expectEqual(store.activeTerms(), [], "two observations should leave the term suggested, not active")
        expectEqual(
            store.entries.first { $0.term == "Rushat" }?.status,
            .suggested
        )

        store.observe(candidateTerms: ["Rushat"])
        expectEqual(store.activeTerms(), ["Rushat"], "the third observation should activate the term")
        expectEqual(
            store.entries.first { $0.term == "Rushat" }?.observationCount,
            3
        )
    }

    // MARK: - caps + eviction

    private static func testSuggestionCapEvictsWeakestSuggestion() {
        let (defaults, suite) = makeDefaults("suggestion-cap")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        // Fill the suggestion cap with distinct single-observation
        // suggestions, oldest first.
        for i in 0..<DictionaryStore.suggestionLimit {
            store.observe(candidateTerms: ["Term\(i)"])
        }
        expectEqual(
            store.entries.filter { $0.status == .suggested }.count,
            DictionaryStore.suggestionLimit
        )
        expectEqual(store.entries.contains { $0.term == "Term0" }, true)

        // A new distinct candidate should evict the weakest suggestion
        // (lowest observationCount, then oldest updatedAt) rather than being
        // dropped or exceeding the cap.
        store.observe(candidateTerms: ["Overflow"])
        expectEqual(
            store.entries.filter { $0.status == .suggested }.count,
            DictionaryStore.suggestionLimit,
            "the cap must still hold after the new candidate is admitted"
        )
        expectEqual(
            store.entries.contains { $0.term == "Term0" },
            false,
            "the oldest, weakest suggestion should have been evicted"
        )
        expectEqual(store.entries.contains { $0.term == "Overflow" }, true)
    }

    private static func testLearnedCapBlocksNewCandidatesWhenNoSuggestionCanBeEvicted() {
        let (defaults, suite) = makeDefaults("learned-cap")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        // Activate exactly learnedEntryLimit distinct learned entries. Active
        // learned entries are never evicted, so once this many exist there is
        // no suggestion left to evict to make room for a new candidate.
        for i in 0..<DictionaryStore.learnedEntryLimit {
            let term = "Learned\(i)"
            store.observe(candidateTerms: [term])
            store.observe(candidateTerms: [term])
            store.observe(candidateTerms: [term])
        }
        expectEqual(
            store.entries.filter { $0.source == .learned && $0.status != .rejected }.count,
            DictionaryStore.learnedEntryLimit
        )
        expectEqual(
            store.entries.filter { $0.status == .suggested }.count,
            0,
            "all learned entries should be active, leaving nothing to evict"
        )

        store.observe(candidateTerms: ["OneTooMany"])
        expectEqual(
            store.entries.contains { $0.term == "OneTooMany" },
            false,
            "a new candidate should be dropped when the learned cap is full and no suggestion can be evicted"
        )
        expectEqual(
            store.entries.filter { $0.source == .learned && $0.status != .rejected }.count,
            DictionaryStore.learnedEntryLimit
        )
    }

    // MARK: - rejected stays rejected

    private static func testRejectedStaysRejected() {
        let (defaults, suite) = makeDefaults("rejected")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        store.observe(candidateTerms: ["Foo"])
        guard let id = store.entries.first(where: { $0.term == "Foo" })?.id else {
            fatalError("expected Foo to be observed")
        }
        store.reject(id: id)
        expectEqual(store.entries.first { $0.term == "Foo" }?.status, .rejected)

        // Repeated observation must never resurrect a rejected term, no
        // matter how many times it recurs.
        for _ in 0..<5 {
            store.observe(candidateTerms: ["Foo"])
        }
        let entry = store.entries.first { $0.term == "Foo" }
        expectEqual(entry?.status, .rejected)
        expectEqual(entry?.observationCount, 1, "observations after rejection must not accrue")
        expectEqual(store.activeTerms().contains("Foo"), false)
        expectEqual(store.entries.filter { $0.term == "Foo" }.count, 1, "no duplicate entry should be created")
    }

    // MARK: - migration idempotence

    private static func testMigrationIsIdempotentAndRespectsPersistedFlag() {
        let (defaults, suite) = makeDefaults("migration")
        defer { defaults.removePersistentDomain(forName: suite) }

        let store1 = DictionaryStore(defaults: defaults)
        store1.migrateLegacyVocabularyIfNeeded(
            rawVocabulary: "Alpha, Beta\nspoken -> replacement\n# a comment\nGamma"
        )
        expectEqual(Set(store1.entries.map(\.term)), Set(["Alpha", "Beta", "Gamma"]))
        expectEqual(store1.entries.allSatisfy { $0.source == .manual && $0.status == .active }, true)

        // A second call on the same instance, even with different text, adds
        // nothing once the migration flag is set.
        store1.migrateLegacyVocabularyIfNeeded(rawVocabulary: "Delta, Epsilon")
        expectEqual(store1.entries.count, 3)
        expectEqual(store1.entries.contains { $0.term == "Delta" }, false)

        // A fresh store instance backed by the same UserDefaults suite must
        // also respect the persisted flag.
        let store2 = DictionaryStore(defaults: defaults)
        store2.migrateLegacyVocabularyIfNeeded(rawVocabulary: "Zeta")
        expectEqual(store2.entries.count, 3)
        expectEqual(store2.entries.contains { $0.term == "Zeta" }, false)
    }

    // MARK: - importPlainTerms

    private static func testImportPlainTermsSkipsCorrectionsAndComments() {
        let (defaults, suite) = makeDefaults("import-plain")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        store.importPlainTerms(fromLegacyText: "Alpha, Beta\nteh -> the\n# a comment\nGamma; Delta")
        expectEqual(Set(store.entries.map(\.term)), Set(["Alpha", "Beta", "Gamma", "Delta"]))
        expectEqual(store.entries.contains { $0.term == "teh" }, false)
        expectEqual(store.entries.contains { $0.term == "the" }, false)

        // Unlike migrateLegacyVocabularyIfNeeded, importPlainTerms is not
        // guarded by a one-time flag, so a later call still lands its terms.
        store.importPlainTerms(fromLegacyText: "Epsilon")
        expectEqual(store.entries.contains { $0.term == "Epsilon" }, true)
    }

    private static func testImportPlainTermsCommaInsideCorrectionReplacementDoesNotLeak() {
        let (defaults, suite) = makeDefaults("import-comma")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        // The line is split on newlines first, so the correction line
        // (including the comma inside its replacement) is evaluated whole
        // and skipped -- none of its comma-separated pieces should leak in
        // as plain terms.
        store.importPlainTerms(fromLegacyText: "hte -> the, then\nRealTerm")
        expectEqual(Set(store.entries.map(\.term)), Set(["RealTerm"]))
        expectEqual(store.entries.contains { $0.term == "the" }, false)
        expectEqual(store.entries.contains { $0.term == "then" }, false)
        expectEqual(store.entries.contains { $0.term == "hte" }, false)
    }

    // MARK: - manual add dedup

    private static func testAddManualPromotesExistingLearnedEntryAndDedupsCaseAndDiacriticInsensitively() {
        let (defaults, suite) = makeDefaults("manual-dedup")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        store.observe(candidateTerms: ["Widget"])
        store.observe(candidateTerms: ["Widget"])
        expectEqual(store.entries.first { $0.term == "Widget" }?.status, .suggested)

        // Manually typing the same term (different case) promotes the
        // existing learned entry to an active manual one instead of
        // duplicating it.
        guard let promoted = try? store.addManual(term: "widget") else {
            fatalError("expected addManual to succeed for a non-active existing term")
        }
        expectEqual(promoted.status, .active)
        expectEqual(promoted.source, .manual)
        expectEqual(store.entries.count, 1)
        expectEqual(store.entries.first?.term, "widget")

        // Now that it is active, adding it again is a duplicate.
        do {
            _ = try store.addManual(term: "Widget")
            fatalError("expected duplicateTerm to be thrown")
        } catch DictionaryStoreError.duplicateTerm {
            // expected
        } catch {
            fatalError("unexpected error: \(error)")
        }

        // Case- and diacritic-insensitive duplicate detection also applies
        // between two manual terms.
        _ = try? store.addManual(term: "café")
        do {
            _ = try store.addManual(term: "CAFE")
            fatalError("expected duplicateTerm for a diacritic/case-insensitive match")
        } catch DictionaryStoreError.duplicateTerm {
            // expected
        } catch {
            fatalError("unexpected error: \(error)")
        }
    }

    private static func testAddManualRejectsEmptyTerm() {
        let (defaults, suite) = makeDefaults("manual-empty")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        do {
            _ = try store.addManual(term: "   ")
            fatalError("expected emptyTerm to be thrown")
        } catch DictionaryStoreError.emptyTerm {
            // expected
        } catch {
            fatalError("unexpected error: \(error)")
        }
    }

    // MARK: - activeTerms ordering

    private static func testActiveTermsOrderingAndDisabledExclusion() {
        let (defaults, suite) = makeDefaults("ordering")
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DictionaryStore(defaults: defaults)

        _ = try? store.addManual(term: "Zebra")
        _ = try? store.addManual(term: "Apple")

        for _ in 0..<3 { store.observe(candidateTerms: ["Gizmo"]) }
        for _ in 0..<5 { store.observe(candidateTerms: ["Widget"]) }
        for _ in 0..<4 { store.observe(candidateTerms: ["Doohickey"]) }

        guard let gizmoID = store.entries.first(where: { $0.term == "Gizmo" })?.id else {
            fatalError("expected Gizmo to be active")
        }
        store.setEnabled(false, for: gizmoID)

        expectEqual(
            store.activeTerms(),
            ["Apple", "Zebra", "Widget", "Doohickey"],
            "manual first (alphabetical), then learned by descending observationCount, excluding disabled entries"
        )
    }

    // MARK: - helpers

    private static func makeDefaults(_ name: String) -> (UserDefaults, String) {
        let suiteName = "com.rushatpeace.onspeak.tests.dictionary.\(name).\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("failed to create scratch UserDefaults suite \(suiteName)")
        }
        return (defaults, suiteName)
    }

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
