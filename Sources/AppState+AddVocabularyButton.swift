import AppKit

// MARK: - Add Vocabulary Button Extension

@MainActor
extension AppState {
    /// Adds a word (or words) from the macOS pasteboard to the personal
    /// dictionary as active manual entries. Returns the added text on success,
    /// or nil when there was nothing to add — empty pasteboard, or every word is
    /// already an active dictionary entry. The nil case is the existing
    /// "already added" feedback path: the menu-bar checkmark only flashes on a
    /// non-nil result.
    @discardableResult
    func pasteWordToVocabulary() -> String? {
        // Read text from pasteboard (macOS native clipboard API)
        // Check if there's any non-whitespace content to paste
        guard let pastedString = NSPasteboard.general.string(forType: .string),
              !pastedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // Clean and prepare the new word(s)
        let wordsToAdd = pastedString
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !wordsToAdd.isEmpty else { return nil }

        // Route each word to the personal dictionary. `addManual` folds case and
        // diacritics for dedup and throws `.duplicateTerm` only when the term is
        // already active — the same "nothing new" outcome the old free-form
        // append produced, mapped to the nil return (no checkmark).
        let store = DictionaryStore.shared
        var addedWords: [String] = []
        for word in wordsToAdd {
            do {
                let entry = try store.addManual(term: word)
                addedWords.append(entry.term)
            } catch DictionaryStoreError.duplicateTerm {
                continue
            } catch {
                continue
            }
        }

        guard !addedWords.isEmpty else { return nil }
        return addedWords.joined(separator: ", ")
    }
}

