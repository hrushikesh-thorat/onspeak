import Foundation

enum ShortcutTests {
    static func run() {
        expect(ShortcutBinding.defaultHold == ShortcutPreset.rightCommand.binding, "Hold to Talk should default to Right Command")
        expect(ShortcutBinding.defaultCopyAgain == ShortcutPreset.rightOption.binding, "Paste Again should default to Right Option")

        let configuration = ShortcutConfiguration(
            hold: .defaultHold,
            copyAgain: .defaultCopyAgain
        )
        var state = ShortcutInputState()

        var result = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 54, isDown: true),
            configuration: configuration
        )
        expect(result.emittedEvents == [.holdActivated], "Right Command should activate Hold to Talk")
        state = result.state

        result = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 54, isDown: false),
            configuration: configuration
        )
        expect(result.emittedEvents == [.holdDeactivated], "Releasing Right Command should stop Hold to Talk")
        state = result.state

        result = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )
        expect(result.emittedEvents == [.copyAgainTriggered], "Right Option should trigger Paste Again")
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
