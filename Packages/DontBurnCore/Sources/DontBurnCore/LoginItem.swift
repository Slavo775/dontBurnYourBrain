/// The app's login item as the system reports it.
public enum LoginItemStatus: Sendable {
    /// Not registered, so the app does not start at login.
    case notRegistered
    /// Registered and allowed, so the app starts at login.
    case enabled
    /// Registered, but switched off in System Settings, where only the user
    /// can switch it on again.
    case requiresApproval
    /// The system does not know the app's login item, as for a build it has
    /// never registered.
    case notFound
}

/// What the Start at login switch shows: whether it is on, and the line under it.
public struct LoginItemSwitch: Equatable, Sendable {
    /// The line under the switch.
    public enum Note: Equatable, Sendable {
        /// Switched off in System Settings, where the user can switch it on again.
        case offInSystemSettings
        /// The system refused the last change, for `reason`, in the system's own words.
        case refused(reason: String)
    }

    /// Whether the switch is on: only while the app starts at login.
    public let isOn: Bool
    /// The line under the switch, or `nil` for none.
    public let note: Note?

    /// The switch for `status`, read from the system, after a change the
    /// system refused for `refusal`, or after none when it is `nil`.
    ///
    /// The switch is on only for ``LoginItemStatus/enabled``, so a refused
    /// registration leaves it off. Switched off in System Settings, the note
    /// says so even after a refusal, because that is the reason.
    public init(status: LoginItemStatus, refusal: String? = nil) {
        isOn = status == .enabled
        note = status == .requiresApproval ? .offInSystemSettings : refusal.map { .refused(reason: $0) }
    }
}

/// How the Dev build shows the Start at login switch for a check, from its
/// `-DontBurnLoginItem` launch argument. Without one, Dev leaves the switch
/// out. Dev never registers with the system either way, so two builds never
/// both start at login.
public enum LoginItemCheck: String, Sendable {
    /// The Dev build's own status, read from the system, with the switch disabled.
    case system
    /// A stand-in in memory that starts off and follows the switch.
    case standIn = "stand-in"
    /// A stand-in in memory that refuses every registration.
    case refuse
    /// A stand-in in memory that was switched off in System Settings.
    case approval

    /// The check `raw` names, from the launch argument.
    ///
    /// The value is input from outside the app. Anything but one of the raw
    /// values, exactly, is `nil`.
    public init?(launchArgument raw: String?) {
        guard let raw, raw.utf8.count <= 16 else { return nil }
        self.init(rawValue: raw)
    }
}
