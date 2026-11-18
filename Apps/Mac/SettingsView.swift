import DontBurnCore
import SwiftData
import SwiftUI
import UserNotifications

/// The Settings window: General and Workspaces for now.
struct SettingsView: View {
    /// The open store, or `nil` when it could not be opened.
    let container: ModelContainer?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralPane()
            }
            Tab("Workspaces", systemImage: "square.grid.2x2") {
                if let container {
                    WorkspacesPane()
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "The data could not be opened",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Workspaces can't be shown or changed right now."),
                    )
                }
            }
        }
        // One fixed size for every tab, the prototype's 760 pt, so the window
        // neither jumps between launches nor between tabs.
        .frame(width: 760, height: 470)
    }
}

/// The General tab: the alerts' switches, and the app's version at the bottom.
private struct GeneralPane: View {
    @State private var isNotificationRefused = false

    var body: some View {
        Form {
            AlertSection("When a block ends", kind: .blockEnd)
            AlertSection("When a break ends", kind: .breakEnd)
            AlertSection("5 minutes before a block ends", kind: .warning)
            if isNotificationRefused {
                Section {
                    HStack {
                        let app = Bundle.main.displayName
                        Label(
                            "Notifications are off for \(app). Allow them in System Settings → Notifications.",
                            systemImage: "exclamationmark.triangle",
                        )
                        Spacer()
                        Button("Open") {
                            // Only the pane. The app never changes the setting itself.
                            NSWorkspace.shared.open(Self.notificationSettings)
                        }
                    }
                }
            }
            Section {
                Text("Version \(Bundle.main.version)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .task { await readPermission() }
        // Back from System Settings, the note follows the new answer. A task,
        // since the answer comes asynchronously and `onReceive` cannot wait.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await readPermission() }
        }
    }

    /// The Notifications pane of System Settings.
    private static let notificationSettings = URL(
        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
    ) ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")

    private func readPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        isNotificationRefused = status == .denied
    }
}

/// One alert's two switches: its notification and its sound.
private struct AlertSection: View {
    let title: LocalizedStringKey
    let kind: AlertKind
    @AppStorage private var notifies: Bool
    @AppStorage private var plays: Bool

    init(_ title: LocalizedStringKey, kind: AlertKind) {
        self.title = title
        self.kind = kind
        _notifies = AppStorage(wrappedValue: AlertSettings.standard.notifications.contains(kind), kind.notificationKey)
        _plays = AppStorage(wrappedValue: AlertSettings.standard.sounds.contains(kind), kind.soundKey)
    }

    var body: some View {
        Section(title) {
            Toggle("Notification", isOn: $notifies)
            Toggle("Sound (\(kind.soundName))", isOn: $plays)
        }
    }
}

/// A button that opens the Settings window and brings it in front of other apps.
///
/// The app has no Dock icon, so its windows open behind the active app unless
/// the app is activated and the window is ordered front by hand.
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            openSettings()
            // `openSettings` alone leaves the window on the Space it was first
            // opened on, and behind the active app.
            let window = NSApplication.shared.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
            window?.collectionBehavior.insert(.moveToActiveSpace)
            NSApplication.shared.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        .keyboardShortcut(",")
    }
}

extension Bundle {
    /// The version the bundle carries, such as `0.1.0 (1)`.
    var version: String {
        let short = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "\(short) (\(build))"
    }
}

@MainActor
extension ModelContainer {
    /// The sample data in memory, for previews, or `nil` when it could not be made.
    static var sample: ModelContainer? {
        do {
            let container = try ModelStore.inMemory()
            // 2026-01-15 08:41:30 UTC, as in the clock's preview.
            try SampleData.seed(into: container.mainContext, now: Date(timeIntervalSince1970: 1_768_466_490))
            return container
        } catch {
            return nil
        }
    }
}

#Preview("Sample data") {
    SettingsView(container: .sample)
}

#Preview("No store") {
    SettingsView(container: nil)
}
