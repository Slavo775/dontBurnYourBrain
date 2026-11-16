import SwiftUI

@main
struct DontBurnApp: App {
    var body: some Scene {
        MenuBarExtra("Don't Burn Your Brain", systemImage: "brain") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
