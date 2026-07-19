import Foundation

/// Composes finalized and provisional speech-recognition results without
/// allowing provisional text to enter the committed transcript.
struct LiveTranscriptComposer {
    private(set) var finalizedText: AttributedString = ""
    private(set) var volatileText: AttributedString = ""

    /// Feed one result from `SpeechTranscriber.results`.
    mutating func ingest(text: AttributedString, isFinal: Bool) {
        if isFinal {
            finalizedText += text
            volatileText = ""
        } else {
            volatileText = text
        }
    }

    /// What the overlay shows while speaking.
    var previewText: String {
        String((finalizedText + volatileText).characters)
    }

    /// What the pipeline commits. Volatile text never appears here.
    var committedText: String {
        String(finalizedText.characters)
    }
}
