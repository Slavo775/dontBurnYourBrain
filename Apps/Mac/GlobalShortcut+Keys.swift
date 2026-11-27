import AppKit
import Carbon
import DontBurnCore
import SwiftUI

extension GlobalShortcut {
    /// The shortcut as the Mac writes it, such as `⌥Space` or `⌃⌥⌘F12`, with
    /// a letter as the current keyboard layout puts it on that key.
    @MainActor var displayName: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifiers = symbols.filter { self.modifiers.contains($0.0) }.map(\.1).joined()
        let key = Self.namedKeys[keyCode]?.name ?? Self.typedCharacter(keyCode: keyCode)?.uppercased()
        return modifiers + (key ?? String(localized: "Key \(keyCode)"))
    }

    /// The shortcut for a menu item, which shows it at the item's right, or
    /// `nil` for a key no character stands for.
    @MainActor var keyboardShortcut: KeyboardShortcut? {
        guard let character = Self.namedKeys[keyCode]?.character ?? Self.typedCharacter(keyCode: keyCode)?.first
        else { return nil }
        let pairs: [(Modifiers, SwiftUI.EventModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        let modifiers = pairs.filter { self.modifiers.contains($0.0) }
            .reduce(into: SwiftUI.EventModifiers()) { $0.insert($1.1) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
    }

    /// The modifiers among `flags` that a shortcut keeps.
    static func modifiers(of flags: NSEvent.ModifierFlags) -> Modifiers {
        let pairs: [(NSEvent.ModifierFlags, Modifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        return pairs.filter { flags.contains($0.0) }.reduce(into: Modifiers()) { $0.insert($1.1) }
    }

    /// Keys that type no character, or whose character says little, by
    /// virtual key code: their name and the character a menu uses for them.
    private static let namedKeys: [Int: (name: String, character: Character)] = {
        var keys: [Int: (name: String, character: Character)] = [
            kVK_Space: (String(localized: "Space"), " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"),
            kVK_Delete: ("⌫", "\u{8}"), kVK_Escape: ("⎋", "\u{1B}"), kVK_ANSI_KeypadEnter: ("⌤", "\u{3}"),
            kVK_LeftArrow: ("←", "\u{F702}"), kVK_RightArrow: ("→", "\u{F703}"),
            kVK_DownArrow: ("↓", "\u{F701}"), kVK_UpArrow: ("↑", "\u{F700}"),
            kVK_ForwardDelete: ("⌦", "\u{F728}"), kVK_Home: ("↖", "\u{F729}"), kVK_End: ("↘", "\u{F72B}"),
            kVK_PageUp: ("⇞", "\u{F72C}"), kVK_PageDown: ("⇟", "\u{F72D}"),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
        ]
        for (index, code) in functionKeys.enumerated() {
            // AppKit's NSF1FunctionKey and those after it.
            if let scalar = Unicode.Scalar(0xF704 + index) {
                keys[code] = ("F\(index + 1)", Character(scalar))
            }
        }
        return keys
    }()

    /// The character the key at `keyCode` types in the current keyboard
    /// layout, without modifiers, or `nil` when it types none.
    @MainActor private static func typedCharacter(keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                base, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters,
            )
        }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return status == noErr && !text.isEmpty ? text : nil
    }
}
