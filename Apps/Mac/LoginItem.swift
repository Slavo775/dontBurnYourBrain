import DontBurnCore
import os
import ServiceManagement
import SwiftUI

/// The system's list of the apps that start at login, as the Start at login switch uses it.
@MainActor
protocol LoginItemRegistering: AnyObject {
    /// The app's login item, read from the system on each call.
    var status: LoginItemStatus { get }
    /// Makes the app start at login. Throws the system's reason when it refuses.
    func register() throws
    /// Makes the app no longer start at login. Throws the system's reason when it refuses.
    func unregister() throws
}

/// Why the app's login item was not changed, when the system was never asked.
enum LoginItemRefusal: LocalizedError {
    /// This is the Dev build, which never registers, so the two builds never both start at login.
    case devBuild
    /// The `refuse` check's stand-in, which refuses every registration.
    case standIn

    var errorDescription: String? {
        switch self {
        case .devBuild: String(localized: "The Dev build never starts at login.")
        case .standIn: String(localized: "The stand-in refuses every registration.")
        }
    }
}

/// The app's own login item, through the system's service for login items.
///
/// The service names the item by the app's bundle identifier and shows it in
/// System Settings, Login Items, under the app's name, where the user can
/// switch it off too. The Dev build reads the status but never registers or
/// unregisters.
final class SystemLoginItem: LoginItemRegistering {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        // A state a later system adds is shown as off, which never claims the app starts at login.
        @unknown default: .notFound
        }
    }

    func register() throws {
        guard !BuildInfo.isDevBuild else { throw LoginItemRefusal.devBuild }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard !BuildInfo.isDevBuild else { throw LoginItemRefusal.devBuild }
        try SMAppService.mainApp.unregister()
    }
}

/// A login item in memory, for checks and previews. Nothing reaches the system.
final class StandInLoginItem: LoginItemRegistering {
    private(set) var status: LoginItemStatus
    private let refuses: Bool

    /// A stand-in in `status`, that refuses every registration when `refuses`.
    init(status: LoginItemStatus, refuses: Bool = false) {
        self.status = status
        self.refuses = refuses
    }

    func register() throws {
        // As the system does, which leaves an item switched off in System Settings to the user.
        guard !refuses, status != .requiresApproval else { throw LoginItemRefusal.standIn }
        status = .enabled
    }

    func unregister() {
        status = .notRegistered
    }
}

/// The Start at login switch: what it shows, read from the system whenever
/// Settings asks, and the user's changes. Nothing is registered until the
/// user switches it on.
@MainActor
@Observable
final class LoginItem {
    /// The switch of this build, kept for the life of the app, or `nil` when
    /// Settings leaves it out.
    ///
    /// Release uses the system's service. Dev leaves the switch out unless its
    /// `-DontBurnLoginItem` launch argument names a ``LoginItemCheck``, and
    /// even then never registers.
    static let current = make(check: LoginItemCheck(launchArgument: DontBurnApp.launchArgument("DontBurnLoginItem")))

    /// Whether the switch can be flipped. Not in Dev on the system's service.
    let canChange: Bool
    /// What the switch shows now.
    private(set) var shown: LoginItemSwitch

    @ObservationIgnored private let service: any LoginItemRegistering
    @ObservationIgnored private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "login")

    init(service: any LoginItemRegistering, canChange: Bool) {
        self.service = service
        self.canChange = canChange
        shown = LoginItemSwitch(status: service.status)
    }

    /// Reads the status again, as when Settings shows the switch or the app
    /// comes back from System Settings. It never changes the status.
    func refresh() {
        shown = LoginItemSwitch(status: service.status)
    }

    /// Registers when `isOn`, otherwise unregisters, then shows the status
    /// read again, with the system's reason when it refused.
    func set(_ isOn: Bool) {
        do {
            if isOn {
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
        } catch {
            // The domain and the code only: the description is the system's and is shown, not logged.
            let error = error as NSError
            log.error("The login item was not changed: \(error.domain, privacy: .public) \(error.code)")
            shown = LoginItemSwitch(status: service.status, refusal: error.localizedDescription)
        }
    }

    private static func make(check: LoginItemCheck?) -> LoginItem? {
        guard BuildInfo.isDevBuild else { return LoginItem(service: SystemLoginItem(), canChange: true) }
        return switch check {
        case nil: nil
        case .system: LoginItem(service: SystemLoginItem(), canChange: false)
        case .standIn: LoginItem(service: StandInLoginItem(status: .notRegistered), canChange: true)
        case .refuse: LoginItem(service: StandInLoginItem(status: .notRegistered, refuses: true), canChange: true)
        case .approval: LoginItem(service: StandInLoginItem(status: .requiresApproval), canChange: true)
        }
    }
}

/// Settings, General: the Start at login switch, and a line under it when
/// the item was switched off in System Settings or the system refused a change.
struct LoginItemSection: View {
    let item: LoginItem

    var body: some View {
        Section {
            Toggle("Start at login", isOn: Binding(get: { item.shown.isOn }, set: { item.set($0) }))
                // Named by hand, as the other switches are, so VoiceOver reads it.
                .accessibilityLabel("Start at login")
                .disabled(!item.canChange)
                // On the switch alone, so the note's row appearing never reads
                // the status again, which would drop the reason it shows.
                .onAppear { item.refresh() }
                // Back from System Settings, the switch follows what the user changed there.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    item.refresh()
                }
            switch item.shown.note {
            case .offInSystemSettings:
                HStack {
                    let app = Bundle.main.displayName
                    Label(
                        "Starting at login is off for \(app). Allow it in System Settings → Login Items.",
                        systemImage: "exclamationmark.triangle",
                    )
                    Spacer()
                    Button("Open") {
                        // Only the pane. The app never changes the setting itself.
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            case let .refused(reason):
                Label("macOS refused the change: \(reason)", systemImage: "exclamationmark.triangle")
            case nil:
                EmptyView()
            }
        }
    }
}

#Preview("Switched off in System Settings") {
    Form {
        LoginItemSection(item: LoginItem(service: StandInLoginItem(status: .requiresApproval), canChange: true))
    }
    .formStyle(.grouped)
}

#Preview("Refused") {
    let item = LoginItem(service: StandInLoginItem(status: .notRegistered, refuses: true), canChange: true)
    item.set(true)
    return Form { LoginItemSection(item: item) }
        .formStyle(.grouped)
}
