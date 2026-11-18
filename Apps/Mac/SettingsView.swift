import DontBurnCore
import SwiftData
import SwiftUI

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

/// The General tab. Nothing to set yet, so it names the app and its version.
private struct GeneralPane: View {
    var body: some View {
        Form {
            LabeledContent("Version", value: Bundle.main.version)
        }
        // The same right-aligned labels as the Workspaces form.
        .formStyle(.columns)
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
