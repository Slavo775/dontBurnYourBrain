import DontBurnCore
import SwiftData
import SwiftUI
import UserNotifications

/// A tab of the Settings window. Its name is what the defaults keep.
enum SettingsTab: String {
    case general
    case workspaces
    case rhythm
    case sessions
}

/// Which tab the Settings window shows, so a link elsewhere can choose it.
@MainActor
@Observable
final class SettingsNavigation {
    /// SwiftUI does not remember the tab of a Settings window that is told its
    /// tab, so the app does, and the window opens as it was left.
    private static let key = "settings.tab"

    /// The tab, General when none or an unknown one was kept.
    var tab = UserDefaults.standard.string(forKey: key).flatMap(SettingsTab.init(rawValue:)) ?? .general {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: Self.key) }
    }
}

/// The Settings window: General, Workspaces, Rhythm and Sessions for now.
struct SettingsView: View {
    /// The open store, or `nil` when it could not be opened.
    let container: ModelContainer?
    /// The open local store, this Mac's own, or `nil` when it could not be opened.
    let localContainer: ModelContainer?
    /// The Claude Code profiles and their hook.
    let hookSetup: HookSetup
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane()
            }
            Tab("Workspaces", systemImage: "square.grid.2x2", value: .workspaces) {
                if let container {
                    WorkspacesPane(localContainer: localContainer)
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "The data could not be opened",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Workspaces can't be shown or changed right now."),
                    )
                }
            }
            Tab("Rhythm", systemImage: "clock", value: .rhythm) {
                if let container {
                    RhythmPane()
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "The data could not be opened",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Presets can't be shown or changed right now."),
                    )
                }
            }
            Tab("Sessions", systemImage: "terminal", value: .sessions) {
                SessionsPane(setup: hookSetup)
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
            AlertSection("When a focus interval ends", kind: .focusEnd)
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
                versionLine
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

    /// Version, build and variant, such as "Version 0.1.0 (1) · Dev · 1a2b3c4".
    /// The commit is shown only when the build carries one, which only Dev does.
    private var versionLine: Text {
        let info = BuildInfo.current
        let variant = info.variant.name
        if let commit = info.commit {
            return Text("Version \(info.version) (\(info.build)) · \(variant) · \(commit)")
        }
        return Text("Version \(info.version) (\(info.build)) · \(variant)")
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
                .accessibilityLabel(spoken.notification)
            Toggle("Sound (\(kind.soundName))", isOn: $plays)
                .accessibilityLabel(spoken.sound)
        }
    }

    /// What VoiceOver reads for each switch, so the pairs can be told apart.
    private var spoken: (notification: LocalizedStringKey, sound: LocalizedStringKey) {
        switch kind {
        case .blockEnd: ("When a block ends, notification", "When a block ends, sound")
        case .breakEnd: ("When a break ends, notification", "When a break ends, sound")
        case .focusEnd: ("When a focus interval ends, notification", "When a focus interval ends, sound")
        case .warning: ("5 minutes before a block ends, notification", "5 minutes before a block ends, sound")
        }
    }
}

/// A button that opens the Settings window and brings it in front of other apps.
///
/// The app has no Dock icon, so its windows open behind the active app unless
/// the app is activated and the window is ordered front by hand.
struct OpenSettingsButton: View {
    /// The window's navigation, to open it on the Sessions tab, or `nil` to
    /// open it as it was left.
    var sessionsTab: SettingsNavigation?

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(sessionsTab == nil ? "Settings…" : "Open Settings, Sessions") {
            sessionsTab?.tab = .sessions
            openSettings()
            // `openSettings` alone leaves the window on the Space it was first
            // opened on, and behind the active app.
            let window = NSApplication.shared.windows
                .first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
            window?.collectionBehavior.insert(.moveToActiveSpace)
            NSApplication.shared.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        // A link to one tab takes no key, so ⌘ and comma keep their one meaning.
        .keyboardShortcut(sessionsTab == nil ? KeyboardShortcut(",") : nil)
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

    /// A local store in memory with the sample folders of the projects in
    /// `projects`, for previews, or `nil` when it could not be made.
    ///
    /// The folders are made in a temporary folder named after the bundle
    /// identifier, as the app's own sample folders are. Without a bundle
    /// identifier there is none to name it after, so nothing is made.
    static func sampleFolders(for projects: ModelContainer?) -> ModelContainer? {
        guard let projects, let root = Bundle.main.sampleRoot else { return nil }
        do {
            let container = try ModelStore.localInMemory()
            try SampleData.seedFolders(into: container.mainContext, projects: projects.mainContext, root: root)
            return container
        } catch {
            return nil
        }
    }
}

#Preview("Sample data") {
    let container = ModelContainer.sample
    SettingsView(
        container: container, localContainer: .sampleFolders(for: container), hookSetup: .sample,
        navigation: SettingsNavigation(),
    )
}

#Preview("No store") {
    SettingsView(container: nil, localContainer: nil, hookSetup: .sample, navigation: SettingsNavigation())
}
