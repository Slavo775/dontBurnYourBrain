/// A key pressed together with modifier keys, which the app registers with
/// the system so it works from any app.
///
/// The key is the Mac's virtual key code, the same on every keyboard layout.
public struct GlobalShortcut: Equatable, Sendable {
    /// The modifier keys held with the key.
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// ⌃
        public static let control = Self(rawValue: 1 << 0)
        /// ⌥
        public static let option = Self(rawValue: 1 << 1)
        /// ⇧
        public static let shift = Self(rawValue: 1 << 2)
        /// ⌘
        public static let command = Self(rawValue: 1 << 3)
        /// All four.
        public static let all: Self = [.control, .option, .shift, .command]
    }

    /// The command bar's shortcut when none is chosen: ⌥ Space.
    public static let commandBar = Self(validKeyCode: 49, modifiers: .option)

    /// The virtual key codes of the modifier keys themselves, from right ⌘ to
    /// fn, which never make a shortcut on their own.
    private static let modifierKeyCodes = 54 ... 63

    /// The virtual key code, from 0 to 127.
    public let keyCode: Int
    /// The modifier keys, at least one of ⌘, ⌃ and ⌥.
    public let modifiers: Modifiers

    /// The shortcut, or `nil` when it cannot be one: the key is no key or a
    /// modifier key, a modifier is unknown, or none of ⌘, ⌃ and ⌥ is held.
    /// Shift alone is not enough, since it only types capitals.
    public init?(keyCode: Int, modifiers: Modifiers) {
        guard (0 ... 127).contains(keyCode), !Self.modifierKeyCodes.contains(keyCode),
              Modifiers.all.isSuperset(of: modifiers), !modifiers.subtracting(.shift).isEmpty
        else { return nil }
        self.init(validKeyCode: keyCode, modifiers: modifiers)
    }

    private init(validKeyCode: Int, modifiers: Modifiers) {
        keyCode = validKeyCode
        self.modifiers = modifiers
    }

    /// The shortcut read back from outside, such as the defaults:
    /// `keyCode` and `modifiers` when they make one, otherwise `fallback`.
    public static func remembered(keyCode: Int?, modifiers: Int?, fallback: Self) -> Self {
        guard let keyCode, let modifiers else { return fallback }
        return Self(keyCode: keyCode, modifiers: Modifiers(rawValue: modifiers)) ?? fallback
    }
}
