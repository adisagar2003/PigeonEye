import AppKit
import SwiftUI
import UI

@main
struct PigeonEyeApp: App {
    init() {
        // A SwiftPM executable has no bundle, so it launches as an accessory
        // and never takes focus. This is what makes `swift run PigeonEye`
        // behave like an app — the alternative is an .xcodeproj, which is not
        // diffable and not agent-editable.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("PigeonEye") {
            ReaderScreen()
        }
        .defaultSize(width: 1320, height: 860)
        .windowResizability(.contentMinSize)
    }
}
