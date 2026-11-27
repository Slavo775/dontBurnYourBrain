import AppKit
import DontBurnCore
import SwiftUI

/// The Shortcuts tab: the command bar's global shortcut, which can be
/// switched off and changed. A problem the system reported shows in one line.
struct ShortcutsPane: View {
    @Bindable var shortcut: CommandBarShortcut

    var body: some View {
        Form {
            Section {
                Toggle("Open the command bar with a shortcut", isOn: $shortcut.isOn)
                    // Named by hand, as the other switches are, so VoiceOver reads it.
                    .accessibilityLabel("Open the command bar with a shortcut")
                // Also while off, so new keys can be chosen before anything is registered.
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: shortcut)
                }
                if let problem = shortcut.problem {
                    Label(problem.message, systemImage: "exclamationmark.triangle")
                }
            } header: {
                Text("Command bar")
            } footer: {
                Text("If the shortcut doesn't open the bar, another app may use it.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// A button that shows the shortcut. After a click it takes the next keys
/// pressed as the new shortcut, or Escape to keep the old one. Keys without
/// ⌘, ⌃ or ⌥ are refused.
private struct ShortcutRecorder: View {
    let shortcut: CommandBarShortcut
    @State private var monitor: Any?
    @State private var isRefused = false

    var body: some View {
        HStack {
            if isRefused {
                Text("Use ⌘, ⌃ or ⌥ with the key")
                    .foregroundStyle(.secondary)
            }
            let shown = shortcut.isRecording ? String(localized: "Type the shortcut") : shortcut.shortcut.displayName
            Button {
                if shortcut.isRecording {
                    stop()
                } else {
                    start()
                }
            } label: {
                Text(shown)
                    .frame(minWidth: 120)
            }
            .accessibilityLabel("Shortcut")
            .accessibilityValue(shown)
        }
        .onDisappear { stop() }
    }

    private func start() {
        isRefused = false
        shortcut.isRecording = true
        // Only this app's own keys, so no permission is needed.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode), flags = event.modifierFlags
            MainActor.assumeIsolated { record(keyCode: keyCode, flags: flags) }
            // Every key goes to the recorder while it waits.
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        shortcut.isRecording = false
    }

    private func record(keyCode: Int, flags: NSEvent.ModifierFlags) {
        let modifiers = GlobalShortcut.modifiers(of: flags)
        if keyCode == 53, modifiers.isEmpty {
            isRefused = false
            stop()
            return
        }
        guard let new = GlobalShortcut(keyCode: keyCode, modifiers: modifiers) else {
            isRefused = true
            return
        }
        isRefused = false
        shortcut.shortcut = new
        stop()
    }
}

#Preview {
    ShortcutsPane(shortcut: CommandBarShortcut(defaults: nil, isOnByDefault: true, hotKey: PreviewHotKey()))
        .frame(width: 760, height: 470)
}

/// A hot key that registers nothing, so a preview never takes a shortcut.
@MainActor
private final class PreviewHotKey: HotKeyRegistering {
    func register(_: GlobalShortcut, onPress _: @escaping @MainActor () -> Void) throws(HotKeyProblem) {}
    func unregister() {}
}
