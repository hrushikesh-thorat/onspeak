import AppKit
import SwiftUI

@main
struct OnSpeakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.appState)
        }
    }
}

@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var notificationManager = VocabularyNotificationManager.shared

    var body: some View {
        HStack(spacing: 4) {
            if notificationManager.showCheckmark {
                Image(systemName: "checkmark")
            }
            if appState.isRecording {
                Image(systemName: "record.circle")
            } else if appState.isTranscribing {
                Image(systemName: "ellipsis.circle")
            } else {
                Image(nsImage: OnSpeakMenuBarIcon.templateImage)
                    .renderingMode(.template)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notificationManager.showCheckmark)
    }
}

enum OnSpeakMenuBarIcon {
    static let templateImage: NSImage = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "waveform", accessibilityDescription: "OnSpeak") ?? NSImage()
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
