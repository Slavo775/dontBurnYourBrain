import AppKit
import DontBurnCore
import os
import UserNotifications

/// Plays the alert sounds and keeps the app's pending notifications in step with the timer.
///
/// The notifications carry no sound. The app plays it, so nothing plays
/// twice, and the sound still plays when notifications are not allowed.
/// Without the permission, scheduling is skipped silently and the timer and
/// the sounds work as before.
@MainActor
@Observable
final class AlertCenter {
    /// Whether the permission prompt is waiting for an answer. The panel then says why it was asked.
    private(set) var isAskingPermission = false

    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let presenter = ForegroundPresenter()
    /// The plan last asked for, compared to whole seconds, which is all a notification keeps.
    @ObservationIgnored private var wanted: [PlannedAlert] = []
    /// Each change waits for the one before, so a removal never overtakes an earlier add.
    @ObservationIgnored private var lastChange: Task<Void, Never>?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "alerts")

    init() {
        UserDefaults.standard.register(defaults: AlertKind.defaults)
        // Without a delegate, a notification due while the app is in front, such as with Settings open, is dropped.
        center.delegate = presenter
        // A question about time away does not outlive the app, so neither does its notification.
        center.removeDeliveredNotifications(withIdentifiers: [Self.awayIdentifier])
    }

    /// The switches from Settings, General.
    var settings: AlertSettings {
        let defaults = UserDefaults.standard
        return AlertSettings(
            notifications: Set(AlertKind.allCases.filter { defaults.bool(forKey: $0.notificationKey) }),
            sounds: Set(AlertKind.allCases.filter { defaults.bool(forKey: $0.soundKey) }),
        )
    }

    /// Plays the sound of `kind`, when its switch is on.
    func play(_ kind: AlertKind) {
        guard settings.sounds.contains(kind) else { return }
        NSSound(named: kind.soundName)?.play()
    }

    /// Asks for the permission to notify, only while it was never answered.
    func askPermissionIfUndetermined() {
        enqueue { [self] in
            guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
            isAskingPermission = true
            do {
                let allowed = try await center.requestAuthorization(options: [.alert])
                log.info("Notifications allowed: \(allowed)")
            } catch {
                log.error("Could not ask to notify: \(error.localizedDescription)")
            }
            isAskingPermission = false
            await replacePending(with: wanted)
        }
    }

    /// Replaces the app's pending notifications with `plan`, the one for `now`, when it changed.
    ///
    /// ponytail: a permission given later in System Settings takes effect at
    /// the next change of the plan, such as the next start or pause.
    func schedule(_ plan: [PlannedAlert], at now: Date) {
        // One whose moment has just come may still be on its way to the screen, so its removal waits for a later tick.
        let old = wanted.filter { !(0 ..< 1).contains(now.timeIntervalSince($0.date)) }
        guard plan.map(\.key) != old.map(\.key) else { return }
        wanted = plan
        enqueue { [self] in await replacePending(with: plan) }
    }

    /// Shows at once that he was away for `minutes` and that the panel asks
    /// what it was, replacing the last such notification. Only when
    /// notifications are allowed: this never asks for the permission.
    func notifyAway(minutes: Int) {
        enqueue { [self] in
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Away for \(blockLength(minutes))")
            content.body = String(localized: "Was it work? The answer waits in the panel.")
            do {
                // No trigger: it shows now.
                try await center.add(
                    UNNotificationRequest(identifier: Self.awayIdentifier, content: content, trigger: nil),
                )
            } catch {
                log.error("Could not show the question about time away: \(error.localizedDescription)")
            }
        }
    }

    /// Takes the notification about time away off the screen, once its question is answered or dropped.
    func withdrawAway() {
        enqueue { [self] in
            center.removePendingNotificationRequests(withIdentifiers: [Self.awayIdentifier])
            center.removeDeliveredNotifications(withIdentifiers: [Self.awayIdentifier])
        }
    }

    /// The identifier of the notification about time away, the same each time, so a new one replaces the old.
    private static var awayIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "").away"
    }

    private func enqueue(_ change: @escaping @MainActor () async -> Void) {
        // A task, since the notification center answers asynchronously and the timer's tick does not wait.
        lastChange = Task { [lastChange] in
            await lastChange?.value
            await change()
        }
    }

    private func replacePending(with plan: [PlannedAlert]) async {
        center.removePendingNotificationRequests(withIdentifiers: AlertKind.allCases.map(\.identifier))
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for alert in plan {
            let content = UNMutableNotificationContent()
            (content.title, content.body) = alert.text
            let moment = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: alert.date,
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: moment, repeats: false)
            // Its second has begun, so it was shown already, and adding it again would only take it away.
            guard trigger.nextTriggerDate() != nil else { continue }
            do {
                try await center.add(UNNotificationRequest(
                    identifier: alert.kind.identifier, content: content, trigger: trigger,
                ))
            } catch {
                log.error("Could not schedule a notification: \(error.localizedDescription)")
            }
        }
    }
}

/// Shows a notification as a banner even while the app is in front.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

extension AlertKind {
    /// The macOS system sound each alert plays, from `/System/Library/Sounds`.
    ///
    /// They ship with macOS and are played by name, so no sound file is in
    /// this repository and none needs a license of its own. The owner chose them.
    var soundName: NSSound.Name {
        switch self {
        case .blockEnd: "Submarine"
        case .breakEnd: "Glass"
        case .focusEnd: "Ping"
        case .warning: "Purr"
        }
    }

    /// The defaults key of the notification's switch. The app's own defaults are named after its bundle identifier.
    var notificationKey: String {
        "alert.\(rawValue).notification"
    }

    /// The defaults key of the sound's switch.
    var soundKey: String {
        "alert.\(rawValue).sound"
    }

    /// The switches' values before the user changes any, from ``AlertSettings/standard``.
    static var defaults: [String: Any] {
        let standard = AlertSettings.standard
        return allCases.reduce(into: [:]) { values, kind in
            values[kind.notificationKey] = standard.notifications.contains(kind)
            values[kind.soundKey] = standard.sounds.contains(kind)
        }
    }

    /// The pending notification's identifier, the same each time, so a new one replaces the old.
    var identifier: String {
        "\(Bundle.main.bundleIdentifier ?? "").\(rawValue)"
    }
}

private extension PlannedAlert {
    /// What makes two plans the same notifications: the kind, the second and what the text says.
    var key: String {
        // The rounded seconds stay a Double: a far date must not trap in a conversion to Int.
        "\(kind.rawValue) \(date.timeIntervalSinceReferenceDate.rounded()) \(text)"
    }

    /// The title and the body.
    var text: (String, String) {
        // A workspace may have an empty name, and the text then names none.
        let workspace = workspace ?? ""
        let named = !workspace.isEmpty
        return switch kind {
        case .breakEnd where self.workspace == nil: (
                String(localized: "Break is over"),
                String(localized: "Start a block when you're ready."),
            )
        case .blockEnd: (
                named ? String(localized: "\(workspace) block finished") : String(localized: "Block finished"),
                String(localized: "Time to stop or start the next one."),
            )
        case .breakEnd where waitsForResume: (
                String(localized: "Break is over"),
                named
                    ? String(localized: "Press Resume to go back to \(workspace).")
                    : String(localized: "Press Resume to go back to work."),
            )
        case .breakEnd: (
                String(localized: "Break is over"),
                named ? String(localized: "Back to \(workspace).") : String(localized: "Back to work."),
            )
        case .focusEnd: (
                String(localized: "Time for a break"),
                named
                    ? String(localized: "\(breakMinutes ?? 0) min break from \(workspace).")
                    : String(localized: "\(breakMinutes ?? 0) min break."),
            )
        case .warning: (
                String(localized: "5 minutes left"),
                named
                    ? String(localized: "The \(workspace) block ends soon.")
                    : String(localized: "The block ends soon."),
            )
        }
    }
}
