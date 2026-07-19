import Combine
import Foundation
import os.log

private let dictionaryLog = OSLog(subsystem: "com.rushatpeace.onspeak", category: "Dictionary")

// MARK: - DictionaryEntry

/// One term in the personal dictionary. Manual entries are typed by the user
/// and are active immediately; learned entries are proposed by
/// ``DictionaryTermLearner`` and stay suggestions until they cross the
/// observation threshold (or the user approves them).
struct DictionaryEntry: Codable, Identifiable, Equatable {
    /// Where the term came from. Only `.learned` entries accrue observations or
    /// can be evicted; `.manual` entries are user-owned and never auto-removed.
    enum Source: String, Codable, CaseIterable {
        case manual
        case learned
    }

    /// Lifecycle of a term. `.suggested` learned terms do not yet bias
    /// recognition; `.active` terms do; `.rejected` is a permanent tombstone
    /// that keeps a vetoed term from ever being re-suggested.
    enum Status: String, Codable, CaseIterable {
        case suggested
        case active
        case rejected
    }

    var id: UUID
    var term: String
    var source: Source
    var status: Status
    var isEnabled: Bool
    var observationCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        source: Source,
        status: Status,
        isEnabled: Bool = true,
        observationCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.source = source
        self.status = status
        self.isEnabled = isEnabled
        self.observationCount = observationCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Errors

/// Failures surfaced by manual dictionary edits. Both map to a short,
/// user-facing message the Settings UI can show inline.
enum DictionaryStoreError: LocalizedError, Equatable {
    case emptyTerm
    case duplicateTerm

    var errorDescription: String? {
        switch self {
        case .emptyTerm: return "Enter a word or phrase."
        case .duplicateTerm: return "That word or phrase is already in your dictionary."
        }
    }
}

// MARK: - DictionaryStore

/// Local, on-device store for OnSpeak's personal dictionary — the manual terms
/// the user typed plus the learned terms OnSpeak picked up from successful
/// dictations. Entries persist as JSON in `UserDefaults`; nothing leaves the
/// device.

/// This iteration only defines the store and its API surface; wiring it into
/// the recognition and cleanup pipelines happens in a later stage.
final class DictionaryStore: ObservableObject, @unchecked Sendable {

    // MARK: Tuning

    /// Independent observations a learned term needs before it activates. Set
    /// above one so a single recognition error never pollutes the dictionary.
    static let learningThreshold = 3

    /// Maximum number of non-rejected learned entries (active + suggested).
    /// Recognition biasing has a practical ceiling, so learned growth is
    /// bounded; weakest suggestions are evicted first once the cap is reached.
    static let learnedEntryLimit = 300

    /// Maximum number of pending (suggested) learned entries. Keeps junk
    /// candidates from piling up in the Suggested list faster than the user can
    /// triage them.
    static let suggestionLimit = 100

    static let shared = DictionaryStore()

    // MARK: State

    @Published private(set) var entries: [DictionaryEntry]

    /// The spec's off switch. When `false`, ``observe(candidateTerms:at:)`` is a
    /// no-op, so manual and already-active learned terms keep working but the
    /// Suggested list stops growing. Persisted under `dictionary_learning_enabled`.
    @Published var learningEnabled: Bool {
        didSet { defaults.set(learningEnabled, forKey: learningEnabledKey) }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let migrationKey: String
    private let learningEnabledKey: String

    /// - Parameters:
    ///   - defaults: Backing store; injectable so tests can use an isolated suite.
    ///   - storageKey: JSON blob of every entry.
    ///   - migrationKey: Idempotence flag for the one-time legacy-vocabulary import.
    ///   - learningEnabledKey: The automatic-learning off switch.
    ///
    /// Migration is **not** run here: it needs the legacy vocabulary string,
    /// which the caller passes to ``migrateLegacyVocabularyIfNeeded(rawVocabulary:)``
    /// at launch. The store never reads or mutates the legacy key itself.
    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "dictionary_entries_v1",
        migrationKey: String = "dictionary_migrated_v1",
        learningEnabledKey: String = "dictionary_learning_enabled"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.migrationKey = migrationKey
        self.learningEnabledKey = learningEnabledKey
        self.entries = Self.load(from: defaults, key: storageKey)
        self.learningEnabled = defaults.object(forKey: learningEnabledKey) == nil
            ? true
            : defaults.bool(forKey: learningEnabledKey)
    }

    // MARK: Accessors

    /// Terms that should bias recognition and seed the dynamic-cleanup spelling
    /// reference: every active, enabled entry, **manual first** (alphabetical),
    /// then learned ordered by descending `observationCount` so the
    /// best-attested learned terms lead when a downstream cap trims the list.
    func activeTerms() -> [String] {
        let active = entries.filter { $0.status == .active && $0.isEnabled }
        let manual = active
            .filter { $0.source == .manual }
            .sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        let learned = active
            .filter { $0.source == .learned }
            .sorted { $0.observationCount > $1.observationCount }
        return (manual + learned).map(\.term)
    }

    // MARK: Manual edits

    /// Adds a user-typed term as an active manual entry. If the term already
    /// exists (case- and diacritic-insensitively), it is promoted to an active
    /// manual entry instead of duplicated — so approving a learned suggestion by
    /// re-typing it works — and only an already-active term is rejected as a
    /// duplicate.
    @discardableResult
    func addManual(term rawTerm: String, at date: Date = Date()) throws -> DictionaryEntry {
        let term = Self.cleaned(rawTerm)
        guard !term.isEmpty else { throw DictionaryStoreError.emptyTerm }

        if let index = index(of: term) {
            guard entries[index].status != .active else {
                throw DictionaryStoreError.duplicateTerm
            }
            entries[index].term = term
            entries[index].source = .manual
            entries[index].status = .active
            entries[index].isEnabled = true
            entries[index].updatedAt = date
            persist()
            return entries[index]
        }

        let entry = DictionaryEntry(
            term: term,
            source: .manual,
            status: .active,
            isEnabled: true,
            observationCount: 0,
            createdAt: date,
            updatedAt: date
        )
        entries.append(entry)
        persist()
        return entry
    }

    /// Approves a suggested learned term, activating it ahead of the observation
    /// threshold.
    func approve(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .active
        entries[index].isEnabled = true
        entries[index].updatedAt = Date()
        persist()
    }

    /// Rejects a term. The entry becomes a permanent tombstone so the same term
    /// is never re-suggested, no matter how often it recurs.
    func reject(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .rejected
        entries[index].isEnabled = false
        entries[index].updatedAt = Date()
        persist()
    }

    /// Enables or disables an entry without changing its status, so a term can be
    /// muted from recognition biasing and turned back on later.
    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isEnabled = enabled
        entries[index].updatedAt = Date()
        persist()
    }

    /// Deletes an entry outright. Unlike ``reject(id:)`` this leaves no
    /// tombstone, so a deleted learned term can be learned again later.
    func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    // MARK: Learning

    /// Records terms proposed by ``DictionaryTermLearner`` for one finished
    /// dictation. A term is counted at most once per call, and a learned term
    /// activates only after ``learningThreshold`` separate calls observe it — a
    /// one-off recognition mistake never activates. No-op when
    /// ``learningEnabled`` is `false`.
    func observe(candidateTerms: [String], at date: Date = Date()) {
        guard learningEnabled else { return }

        // Collapse duplicates within this single dictation: recurring within one
        // transcript still counts as one observation.
        let uniqueTerms = Dictionary(
            grouping: candidateTerms.map(Self.cleaned).filter { !$0.isEmpty }
        ) { Self.canonical($0) }
        .compactMap { $0.value.first }

        guard !uniqueTerms.isEmpty else { return }

        boundRejectedTombstones()

        for term in uniqueTerms {
            if let index = index(of: term) {
                // Manual terms and rejected learned terms are immutable here:
                // manual entries are user-owned, and a rejection is permanent.
                guard entries[index].source == .learned,
                      entries[index].status != .rejected else { continue }
                entries[index].observationCount += 1
                if entries[index].observationCount >= Self.learningThreshold {
                    entries[index].status = .active
                }
                entries[index].updatedAt = date
            } else if makeRoomForNewLearnedEntry() {
                entries.append(DictionaryEntry(
                    term: term,
                    source: .learned,
                    status: Self.learningThreshold <= 1 ? .active : .suggested,
                    isEnabled: true,
                    observationCount: 1,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }
        persist()
    }

    // MARK: Migration

    /// One-time import of the legacy free-form vocabulary string into manual
    /// entries. Plain terms become active manual entries; `->` / `=>` correction
    /// lines and `#` comments are left alone (they stay in the corrections text
    /// box). Idempotent: guarded by the `dictionary_migrated_v1` flag so it runs
    /// at most once, and the passed-in `rawVocabulary` string is only read,
    /// never written back, so a downgrade still finds its data intact.
    func migrateLegacyVocabularyIfNeeded(rawVocabulary: String) {
        guard !defaults.bool(forKey: migrationKey) else { return }
        importPlainTerms(fromLegacyText: rawVocabulary)
        defaults.set(true, forKey: migrationKey)
    }

    /// Imports the plain-vocabulary terms of a legacy-format text into the
    /// dictionary as active manual entries, skipping correction lines and
    /// comments. Unlike `migrateLegacyVocabularyIfNeeded` this is not guarded,
    /// so callers that collect vocabulary after migration already ran (the
    /// first-run setup step) can still land their terms in the dictionary.
    func importPlainTerms(fromLegacyText rawVocabulary: String) {
        let now = Date()
        // Split on newlines first so a correction line is evaluated whole: a
        // comma inside a replacement must not leak half of the mapping into the
        // dictionary. Only the plain-vocabulary lines are then comma/semicolon
        // split into individual terms, matching how the shared box is read.
        for rawLine in rawVocabulary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard !line.contains("->"), !line.contains("=>") else { continue }

            let terms = line
                .components(separatedBy: CharacterSet(charactersIn: ",;"))
                .map(Self.cleaned)
                .filter { !$0.isEmpty }
            for term in terms where index(of: term) == nil {
                entries.append(DictionaryEntry(
                    term: term,
                    source: .manual,
                    status: .active,
                    isEnabled: true,
                    createdAt: now,
                    updatedAt: now
                ))
            }
        }
        persist()
    }

    // MARK: Eviction

    /// Makes room for one new learned suggestion while honoring both caps.
    /// Weakest entries go first — lowest `observationCount`, then oldest — and
    /// only pending suggestions are evicted; an active learned term (the payoff
    /// of learning) is never dropped to admit a fresh candidate. Returns `false`
    /// when no room can be freed, in which case the candidate is skipped.
    private func makeRoomForNewLearnedEntry() -> Bool {
        while suggestionCount >= Self.suggestionLimit {
            guard evictWeakestSuggestion() else { return false }
        }
        while learnedCount >= Self.learnedEntryLimit {
            guard evictWeakestSuggestion() else { return false }
        }
        return true
    }

    /// Non-rejected learned entries (active + suggested) counted against
    /// ``learnedEntryLimit``.
    private var learnedCount: Int {
        entries.reduce(0) { $0 + ($1.source == .learned && $1.status != .rejected ? 1 : 0) }
    }

    /// Pending learned suggestions counted against ``suggestionLimit``.
    private var suggestionCount: Int {
        entries.reduce(0) { $0 + ($1.source == .learned && $1.status == .suggested ? 1 : 0) }
    }

    /// Removes the weakest pending suggestion (lowest `observationCount`, then
    /// oldest `updatedAt`). Returns `false` when there is no suggestion to evict.
    @discardableResult
    private func evictWeakestSuggestion() -> Bool {
        let victim = entries.indices
            .filter { entries[$0].source == .learned && entries[$0].status == .suggested }
            .min { lhs, rhs in
                if entries[lhs].observationCount != entries[rhs].observationCount {
                    return entries[lhs].observationCount < entries[rhs].observationCount
                }
                return entries[lhs].updatedAt < entries[rhs].updatedAt
            }
        guard let victim else { return false }
        entries.remove(at: victim)
        return true
    }

    /// Bounds the permanent rejected-term tombstones so vetoing thousands of
    /// junk suggestions can't grow storage without limit. Only the most recent
    /// ``learnedEntryLimit`` rejections are retained.
    private func boundRejectedTombstones() {
        let rejected = entries
            .filter { $0.source == .learned && $0.status == .rejected }
            .sorted { $0.updatedAt < $1.updatedAt }
        guard rejected.count > Self.learnedEntryLimit else { return }
        let expiredIDs = Set(rejected.prefix(rejected.count - Self.learnedEntryLimit).map(\.id))
        entries.removeAll { expiredIDs.contains($0.id) }
    }

    // MARK: Persistence

    private func index(of term: String) -> Int? {
        let canonicalTerm = Self.canonical(term)
        return entries.firstIndex { Self.canonical($0.term) == canonicalTerm }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else {
            os_log(.error, log: dictionaryLog, "failed to encode dictionary entries for persistence")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// Loads entries, returning an empty set when nothing is stored or the blob
    /// is corrupt. On corruption the learned set is lost but manual terms are
    /// recoverable by re-running migration from the untouched legacy vocabulary.
    private static func load(from defaults: UserDefaults, key: String) -> [DictionaryEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            os_log(.error, log: dictionaryLog, "failed to decode dictionary entries; starting empty")
            return []
        }
        return decoded
    }

    // MARK: Normalization

    /// Trims and collapses internal whitespace so "  Core   ML " and "Core ML"
    /// are stored identically.
    private static func cleaned(_ term: String) -> String {
        term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Case- and diacritic-insensitive folding used for dedup, so "café" and
    /// "cafe" collapse to one entry.
    private static func canonical(_ term: String) -> String {
        cleaned(term).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
