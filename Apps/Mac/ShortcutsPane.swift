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
/// pressed in its own window as the new shortcut, or Escape to keep the old
/// one. Keys without ⌘, ⌃ or ⌥, and apps' ⌘ commands, are refused with their
/// reason. Recording stops when the window is no longer the key window.
private struct ShortcutRecorder: View {
    let shortcut: CommandBarShortcut
    @State private var monitor: Any?
    @State private var refusal: Refusal?
    @Environment(\.controlActiveState) private var activeState

    private enum Refusal {
        case noModifier, appCommand
    }

    var body: some View {
        HStack {
            switch refusal {
            case .noModifier:
                Text("Use ⌘, ⌃ or ⌥ with the key")
                    .foregroundStyle(.secondary)
            case .appCommand:
                Text("Apps use ⌘ with this key. Add ⌃ or ⌥")
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
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
        // Closing the window also takes its key state first.
        .onChange(of: activeState) {
            if activeState != .key {
                stop()
            }
        }
    }

    private func start() {
        refusal = nil
        // The button was just clicked, so its window is the key window.
        let window = NSApp.keyWindow?.windowNumber
        shortcut.isRecording = true
        // Only this app's own keys, so no permission is needed.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode), flags = event.modifierFlags
            let isTaken = MainActor.assumeIsolated {
                // Keys go to the key window, so only keys while its own window is key are the recorder's.
                guard window != nil, NSApp.keyWindow?.windowNumber == window else { return false }
                record(keyCode: keyCode, flags: flags)
                return true
            }
            // Every key in the recorder's window goes to it while it waits.
            return isTaken ? nil : event
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
            refusal = nil
            stop()
            return
        }
        guard let new = GlobalShortcut(keyCode: keyCode, modifiers: modifiers) else {
            let isAppCommand = GlobalShortcut.isAppCommand(keyCode: keyCode, modifiers: modifiers)
            refusal = isAppCommand ? .appCommand : .noModifier
            return
        }
        refusal = nil
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
