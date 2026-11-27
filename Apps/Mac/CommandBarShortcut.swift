import DontBurnCore
import Foundation

/// The command bar's global shortcut: whether it is on, its keys, and what
/// the system said when it was registered.
///
/// Kept in the app's own defaults, as `commandBar.shortcutOn`,
/// `commandBar.keyCode` and `commandBar.modifiers`, or in memory only
/// without them, as for the sample data. On by default in the Release build
/// and off in Dev, so two builds never fight over one shortcut. A change
/// registers again at once.
@MainActor
@Observable
final class CommandBarShortcut {
    static let isOnKey = "commandBar.shortcutOn"
    static let keyCodeKey = "commandBar.keyCode"
    static let modifiersKey = "commandBar.modifiers"

    /// Whether the shortcut is registered. Off, nothing is.
    var isOn: Bool {
        didSet {
            defaults?.set(isOn, forKey: Self.isOnKey)
            apply()
        }
    }

    /// The keys that open the bar.
    var shortcut: GlobalShortcut {
        didSet {
            defaults?.set(shortcut.keyCode, forKey: Self.keyCodeKey)
            defaults?.set(shortcut.modifiers.rawValue, forKey: Self.modifiersKey)
            apply()
        }
    }

    /// Whether Settings is waiting for new keys. Meanwhile nothing is
    /// registered, so the keys reach Settings even when they are the current ones.
    var isRecording = false {
        // Only on a change, so closing Settings leaves no gap in which another app could take the shortcut.
        didSet {
            if isRecording != oldValue {
                apply()
            }
        }
    }

    /// What the system refused at the last registration, or `nil`.
    private(set) var problem: HotKeyProblem?

    /// The shortcut registered now, or `nil`.
    private(set) var registered: GlobalShortcut?

    /// Called on each press of the registered shortcut.
    @ObservationIgnored var onPress: @MainActor () -> Void = {}

    @ObservationIgnored private let hotKey: any HotKeyRegistering
    @ObservationIgnored private let defaults: UserDefaults?

    /// The settings kept in `defaults`, or in memory when it is `nil`, on by
    /// default when `isOnByDefault`. A kept shortcut that makes none falls
    /// back to ⌥ Space. Nothing is registered until ``apply()``.
    init(defaults: UserDefaults?, isOnByDefault: Bool, hotKey: any HotKeyRegistering = CarbonHotKey()) {
        self.defaults = defaults
        self.hotKey = hotKey
        isOn = defaults?.object(forKey: Self.isOnKey) as? Bool ?? isOnByDefault
        shortcut = GlobalShortcut.remembered(
            keyCode: defaults?.object(forKey: Self.keyCodeKey) as? Int,
            modifiers: defaults?.object(forKey: Self.modifiersKey) as? Int,
            fallback: .commandBar,
        )
    }

    /// Registers the shortcut while it is on and Settings is not recording,
    /// and unregisters it otherwise.
    func apply() {
        hotKey.unregister()
        registered = nil
        problem = nil
        guard isOn, !isRecording else { return }
        do {
            try hotKey.register(shortcut) { [weak self] in self?.onPress() }
            registered = shortcut
        } catch {
            problem = error
        }
    }
}
