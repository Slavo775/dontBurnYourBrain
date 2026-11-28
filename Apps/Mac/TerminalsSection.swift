import DontBurnCore
import SwiftUI

/// The Terminals section of the Sessions tab: Terminal and iTerm2, each with
/// whether macOS lets the app control it. VS Code and Cursor come with card #52.
struct TerminalsSection: View {
    let terminalFocus: TerminalFocus

    var body: some View {
        Section("Terminals") {
            ForEach(TerminalFocus.terminals, id: \.self) { terminal in
                TerminalRow(terminal: terminal, permission: terminalFocus.permission(of: terminal))
            }
        }
        // Read without asking. Back from System Settings, the rows follow the new answer.
        .task { await terminalFocus.readPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await terminalFocus.readPermissions() }
        }
    }
}

/// One terminal Focus brings forward, and whether macOS lets the app control it.
///
/// The app never asks from here: macOS asks the first time Focus is used for
/// the terminal. Once the user refused, only System Settings can allow it.
private struct TerminalRow: View {
    let terminal: TerminalApp
    let permission: AutomationPermission

    /// Privacy & Security → Automation in System Settings.
    private static let automationSettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
    ) ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentIcon()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: terminal.name)
                Text("Jumps to the exact tab")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if permission == .denied {
                    let app = Bundle.main.displayName
                    Text("Turn on \(terminal.name) for \(app) in System Settings → Privacy & Security → Automation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            switch permission {
            case .allowed:
                StatusChip(text: "allowed", isPositive: true)
            case .denied:
                Button("Allow") {
                    // Only the pane. The app never changes the setting itself.
                    NSWorkspace.shared.open(Self.automationSettings)
                }
            case .notAsked:
                StatusChip(text: "asked at the first Focus", isPositive: false)
            case .notRunning:
                StatusChip(text: "not running", isPositive: false)
            case .unknown:
                EmptyView()
            }
        }
    }
}

#Preview("Sample data") {
    Form {
        TerminalsSection(terminalFocus: TerminalFocus(isSample: true))
    }
    .formStyle(.grouped)
    .frame(width: 760)
}

#Preview("Every state") {
    let states: [AutomationPermission] = [.allowed, .denied, .notAsked, .notRunning, .unknown]
    Form {
        ForEach(states.indices, id: \.self) { index in
            TerminalRow(terminal: .iTerm2, permission: states[index])
        }
    }
    .formStyle(.grouped)
    .frame(width: 760)
}
