import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - DynamicCleanupEval
//
// Manual golden-case eval harness for `AppleFoundationModelsPostProcessor`
// (spec 001, "Testing" section). This is a TUNING TOOL, not a CI gate: it
// runs real transcripts through Apple's on-device Foundation Models and
// prints a pass/diff table so the ported prompt can be tuned against
// real model behavior. It always exits 0 — a diff is data, not a failure.
//
// Compiled as a SEPARATE binary from the `make test` runner (see the
// Makefile `eval` target), so this file owns its own `@main` with no
// collision against `Tests/AppContextServiceTests.swift`.
//
// Production fidelity: each spoken input is run through
// `TranscriptTidier.tidy` (no corrections) before it reaches the model,
// exactly as `AppState.processTranscript` does, and a fresh prewarmed
// session is prepared per case (every real dictation prewarms its own
// session). Both mirror production so a diff reflects the prompt, not a
// harness artifact such as a cold, reused session.
//
// Golden-case provenance:
//   - Self-correction, dictated-punctuation, and developer-syntax examples
//     are adapted from the retired cloud prompt's documented behaviors
//     (`Sources/PostProcessingService.swift`, `defaultSystemPrompt`).
//   - Instruction-preservation cases assert the model never generates the
//     content an embedded instruction describes — it only cleans the
//     literal spoken words.
//   - The anchor cases originally quoted `AppleFoundationModelsPostProcessor
//     .instructions` verbatim. The 0.3.x tuning pass replaced the prompt's
//     baked-in examples with clearly artificial spans (so example content can
//     never leak into real output), so the anchors now exercise the underlying
//     rules without echoing the prompt's own example sentences.
//
// IMPORTANT — divergences from the retired cloud prompt, deliberately NOT
// carried into these expectations (per the ported prompt's actual contract,
// not the old cloud prompt's aspirational one):
//   1. Email formatting (salutation-then-blank-line-then-body, closing
//      paragraphs, spoken "new line" -> literal newline) has NO equivalent
//      in the ported `instructions` string. The old cloud prompt specified
//      this explicitly under "Formatting"; the ported prompt says nothing
//      about email structure at all. The dictated-punctuation case below
//      therefore only exercises word-to-symbol punctuation conversion
//      ("comma" -> ","), not salutation/closing layout — a diff on layout
//      would not be a prompt bug, it would be untested surface.
//   2. The old cloud prompt explicitly guarded against corrupting the
//      *source* span in developer-syntax rewrites ("rename user id to
//      user_id", not "rename user_id to user_id"). The ported prompt's
//      developer-syntax guidance is a single generic sentence with no such
//      guard. The `rename-user-id` case below still encodes the desired
//      (guarded) behavior as `expected`, but a diff there is a plausible
//      prompt gap, not a harness bug — flagged inline below.
//   3. Multi-language self-correction markers (Romanian "nu", Spanish
//      "no, perdón", French "non") from the old prompt are not covered:
//      the ported prompt makes no per-language promises, so only English
//      markers are exercised here.

struct GoldenCase {
    let name: String
    let spoken: String
    let expected: String
    /// Additional outputs that also count as a PASS. Used sparingly, only
    /// where more than one cleaned form is legitimately correct (e.g. an
    /// optional discourse-filler that the model may keep or drop).
    var alternates: [String] = []
}

let goldenCases: [GoldenCase] = [
    // MARK: Anchors — one high-value case per core behavior the prompt targets
    // (tone/hedge preservation, developer-syntax conversion, self-correction,
    // instruction preservation). These were once quoted verbatim from the
    // prompt, but the 0.3.x tuning pass replaced the prompt's baked-in examples
    // with clearly artificial spans (so example content can't leak into real
    // output), so these now exercise the rules rather than echo their examples.
    GoldenCase(
        name: "anchor-tone-preservation",
        spoken: "I think we should ship this tomorrow",
        expected: "I think we should ship this tomorrow."
    ),
    GoldenCase(
        name: "anchor-dev-syntax-force-with-lease",
        spoken: "The command is git push dash dash force with lease, and then check the JSON output",
        expected: "The command is git push --force-with-lease, and then check the JSON output."
    ),
    GoldenCase(
        name: "anchor-self-correction-wednesday",
        spoken: "Let's meet Thursday, no actually Wednesday after lunch",
        expected: "Let's meet Wednesday after lunch."
    ),
    GoldenCase(
        name: "anchor-instruction-preservation-john",
        spoken: "Write a message to John saying I'm running late",
        expected: "Write a message to John saying I'm running late."
    ),

    // MARK: Self-correction (retired cloud prompt examples, English-only per divergence note 3).
    GoldenCase(
        name: "self-correction-spec-checklist",
        spoken: "let's meet Thursday no actually Wednesday",
        expected: "Let's meet Wednesday."
    ),
    GoldenCase(
        name: "self-correction-wait-i-mean",
        spoken: "call him at 3 wait I mean 4 pm",
        expected: "Call him at 4 PM."
    ),
    GoldenCase(
        name: "self-correction-no-sorry",
        spoken: "the meeting is in room 202 no sorry room 204",
        expected: "The meeting is in room 204."
    ),

    // MARK: Dictated punctuation (divergence note 1: layout-only surface excluded).
    GoldenCase(
        name: "dictated-punctuation-comma",
        spoken: "hi dana comma thanks for the update",
        expected: "Hi Dana, thanks for the update."
    ),

    // MARK: Developer syntax.
    GoldenCase(
        name: "dev-syntax-dash-fix",
        spoken: "dash dash fix",
        expected: "--fix"
    ),
    GoldenCase(
        name: "dev-syntax-npm-flags",
        spoken: "run npm install dash dash save dash dev",
        expected: "Run npm install --save-dev."
    ),
    // Divergence note 2: expects the source span ("user id") to stay
    // untouched while only the explicitly-dictated target ("user underscore
    // id") converts. The ported prompt has no explicit guard for this; a
    // diff here (e.g. both spans converted) is plausible prompt-tuning data,
    // not a harness error.
    GoldenCase(
        name: "dev-syntax-rename-user-id",
        spoken: "rename user id to user underscore id",
        expected: "Rename user id to user_id."
    ),

    // MARK: Instruction preservation — expected output is the cleaned
    // verbatim transcript, never generated content.
    GoldenCase(
        name: "instruction-preservation-poem",
        spoken: "make a poem about the moon",
        expected: "Make a poem about the moon."
    ),
    GoldenCase(
        name: "instruction-preservation-claude-refactor",
        spoken: "ask claude to refactor the auth module",
        expected: "Ask Claude to refactor the auth module."
    ),
    GoldenCase(
        name: "instruction-preservation-email-team",
        spoken: "send an email to the team asking if friday works",
        expected: "Send an email to the team asking if Friday works."
    ),

    // MARK: Plain / near-passthrough.
    GoldenCase(
        name: "plain-earnings",
        spoken: "quarterly earnings beat expectations by twelve percent",
        expected: "Quarterly earnings beat expectations by twelve percent."
    ),
    GoldenCase(
        name: "plain-oxford-comma-list",
        spoken: "please remember to pick up milk eggs and bread on the way home",
        expected: "Please remember to pick up milk, eggs, and bread on the way home."
    ),

    // MARK: Filler / stutter removal.
    GoldenCase(
        name: "filler-duplicate-start",
        spoken: "the the meeting got pushed to friday",
        expected: "The meeting got pushed to Friday."
    ),
    // The leading discourse-filler "so" carries no meaning here, so a model
    // that drops it is equally correct — both forms pass (flagged over-strict
    // in the baseline).
    GoldenCase(
        name: "filler-um-uh",
        spoken: "um so I think we should uh just go with option two",
        expected: "So I think we should just go with option two.",
        // A comma after the discourse-marker "So" is valid punctuation, not a
        // cleanup defect — accepted alongside the comma-less and so-dropped forms.
        alternates: [
            "I think we should just go with option two.",
            "So, I think we should just go with option two.",
        ]
    ),
]

enum EvalOutcome {
    case pass
    case diff(actual: String)
    case errored(String)
}

@main
struct DynamicCleanupEval {
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 1024)

        print("=== OnSpeak Dynamic Cleanup Golden-Case Eval ===")
        print("(tuning tool — not a CI gate; always exits 0)")
        print("")

        let processor = AppleFoundationModelsPostProcessor.shared
        let availability = await processor.availability()
        guard case .available = availability else {
            print("Dynamic Cleanup is unavailable: \(availability.reasonDescription)")
            print("Skipping golden-case eval.")
            return
        }
        print("Availability: available")
        print("Running \(goldenCases.count) case(s) sequentially against the on-device model...")
        print("Each case is tidied (TranscriptTidier.tidy) and run on a fresh prewarmed session, mirroring production.")
        print("")

        var passed = 0
        var diffed = 0
        var errored = 0

        for (index, testCase) in goldenCases.enumerated() {
            let label = "[\(index + 1)/\(goldenCases.count)] \(testCase.name)"
            print("\(label) ... ", terminator: "")
            fflush(stdout)

            // Mirror production warmth: every real dictation prepares and
            // prewarms its own session before cleanup runs, so prepare a fresh
            // one per case here too. A single shared session (as the first
            // baseline used) leaves every case after the first running cold,
            // which manifested as a spurious timeout.
            let sessionID = UUID()
            await processor.prepare(sessionID: sessionID)

            let outcome = await run(testCase, processor: processor, sessionID: sessionID)

            switch outcome {
            case .pass:
                passed += 1
                print("PASS")
            case .diff(let actual):
                diffed += 1
                print("DIFF")
                printDiffBlock(spoken: testCase.spoken, expected: testCase.expected, actual: actual)
            case .errored(let reason):
                errored += 1
                print("ERRORED")
                printErrorBlock(spoken: testCase.spoken, reason: reason)
            }
        }

        print("")
        print("=== Summary ===")
        print("\(passed) passed / \(diffed) diffed / \(errored) errored (\(goldenCases.count) total)")
    }

    private static func run(
        _ testCase: GoldenCase,
        processor: AppleFoundationModelsPostProcessor,
        sessionID: UUID
    ) async -> EvalOutcome {
        // Mirror production: the model always receives the deterministically
        // tidied transcript, not the raw spoken words, so the fallback text is
        // byte-identical to the tidier's output and the model sees the same
        // pre-normalized input it does in `AppState.processTranscript`.
        let tidied = TranscriptTidier.tidy(testCase.spoken)
        let request = DynamicCleanupRequest(transcript: tidied, vocabulary: [])
        do {
            let response = try await processor.cleanup(
                request,
                sessionID: sessionID,
                timeout: AppleFoundationModelsPostProcessor.defaultTimeout
            )
            let actual = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let accepted = ([testCase.expected] + testCase.alternates)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if accepted.contains(actual) {
                return .pass
            }
            return .diff(actual: response.text)
        } catch {
            return .errored(String(describing: error))
        }
    }

    private static func printDiffBlock(spoken: String, expected: String, actual: String) {
        let rule = String(repeating: "-", count: 62)
        print(rule)
        print("  Spoken:   \(spoken)")
        print("  Expected: \(expected)")
        print("  Actual:   \(actual)")
        print(rule)
    }

    private static func printErrorBlock(spoken: String, reason: String) {
        let rule = String(repeating: "-", count: 62)
        print(rule)
        print("  Spoken: \(spoken)")
        print("  Error:  \(reason)")
        print(rule)
    }
}
