import Foundation

@main
struct TestRunner {
    static func main() {
        TranscriptTidierTests.run()
        ShortcutTests.run()
        DynamicCleanupGuardTests.run()
        DictionaryTermLearnerTests.run()
        DictionaryStoreTests.run()
        LiveTranscriptComposerTests.run()
        LiveTranscriptSessionSupportTests.run()
        UpdateCheckerTests.run()
        print("OnSpeakTests passed")
    }
}
