@testable import DontBurnCore
import Testing

typealias ShortcutModifiers = GlobalShortcut.Modifiers

/// ⌃⌥⌘ as the app stores it: ⌃ 1, ⌥ 2, ⇧ 4 and ⌘ 8.
private let controlOptionCommand = 1 | 2 | 8

/// F12's virtual key code.
private let f12 = 111

@Test func `the command bar's shortcut is option space when none is chosen`() {
    #expect(GlobalShortcut.commandBar.keyCode == 49)
    #expect(GlobalShortcut.commandBar.modifiers == .option)
}

@Test func `the modifiers keep the app's own bits`() {
    #expect(ShortcutModifiers.control.rawValue == 1)
    #expect(ShortcutModifiers.option.rawValue == 2)
    #expect(ShortcutModifiers.shift.rawValue == 4)
    #expect(ShortcutModifiers.command.rawValue == 8)
    #expect(ShortcutModifiers.all.rawValue == 15)
}

@Test(arguments: [
    ShortcutModifiers.control, .option, .command, [.shift, .command], [.control, .option, .command], .all,
])
func `a key with command, control or option makes a shortcut`(modifiers: ShortcutModifiers) throws {
    let shortcut = try #require(GlobalShortcut(keyCode: f12, modifiers: modifiers))
    #expect(shortcut.keyCode == f12)
    #expect(shortcut.modifiers == modifiers)
}

@Test(arguments: [ShortcutModifiers(), .shift])
func `a key with no modifier or shift alone makes no shortcut`(modifiers: ShortcutModifiers) {
    #expect(GlobalShortcut(keyCode: 0, modifiers: modifiers) == nil)
    #expect(GlobalShortcut(keyCode: f12, modifiers: modifiers) == nil)
}

@Test(arguments: Array(54 ... 63))
func `a modifier key itself makes no shortcut`(keyCode: Int) {
    #expect(GlobalShortcut(keyCode: keyCode, modifiers: .option) == nil)
}

@Test(arguments: [0, 53, 127])
func `key codes from 0 to 127 outside the modifier keys make a shortcut`(keyCode: Int) {
    #expect(GlobalShortcut(keyCode: keyCode, modifiers: .control)?.keyCode == keyCode)
}

@Test(arguments: [-1, 128, 255, Int.max, Int.min])
func `a key code outside 0 to 127 makes no shortcut`(keyCode: Int) {
    #expect(GlobalShortcut(keyCode: keyCode, modifiers: .option) == nil)
}

@Test(arguments: [16, 2 | 16, 1 << 20, -1])
func `an unknown modifier bit makes no shortcut`(rawValue: Int) {
    #expect(GlobalShortcut(keyCode: f12, modifiers: ShortcutModifiers(rawValue: rawValue)) == nil)
}

@Test func `a remembered shortcut that makes one is read back as it was kept`() throws {
    let kept = try #require(GlobalShortcut(keyCode: f12, modifiers: ShortcutModifiers(rawValue: controlOptionCommand)))
    #expect(GlobalShortcut.remembered(keyCode: f12, modifiers: controlOptionCommand, fallback: .commandBar) == kept)
}

@Test(arguments: [
    (Int?.none, Int?.none), (nil, 2), (111, nil),
    (111, 0), (111, 4), (111, 16), (111, 2 | 16), (56, 2), (128, 2), (-1, 2),
])
func `a remembered shortcut that is missing or makes none falls back`(keyCode: Int?, modifiers: Int?) throws {
    let fallback = try #require(GlobalShortcut(keyCode: f12, modifiers: [.control, .option, .command]))
    #expect(GlobalShortcut.remembered(keyCode: keyCode, modifiers: modifiers, fallback: fallback) == fallback)
    #expect(GlobalShortcut.remembered(keyCode: keyCode, modifiers: modifiers, fallback: .commandBar) == .commandBar)
}

// MARK: - An app's own ⌘ commands

/// Carbon's `kVK_F1` to `kVK_F20`, written out here rather than taken from the product.
private let functionKeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

/// A, W, Q, Return, Escape, Home and the four arrows.
private let commandKeys = [0, 13, 12, 36, 53, 115, 123, 124, 125, 126]

@Test(arguments: [ShortcutModifiers.command, [.command, .shift]])
func `command alone or with shift on a letter, Return, Escape or an arrow is an app's command and no shortcut`(
    modifiers: ShortcutModifiers,
) {
    for keyCode in commandKeys {
        #expect(GlobalShortcut.isAppCommand(keyCode: keyCode, modifiers: modifiers), "key \(keyCode)")
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: modifiers) == nil, "key \(keyCode)")
    }
}

@Test(arguments: [ShortcutModifiers.command, [.command, .shift]])
func `command alone or with shift on Space or an F-key is a shortcut`(modifiers: ShortcutModifiers) {
    #expect(functionKeys.count == 20)
    for keyCode in [49] + functionKeys {
        #expect(!GlobalShortcut.isAppCommand(keyCode: keyCode, modifiers: modifiers), "key \(keyCode)")
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: modifiers)?.keyCode == keyCode, "key \(keyCode)")
    }
}

@Test(arguments: [
    [.command, .control], [.command, .option], [.command, .option, .shift], .all, .control, .option, [.control, .shift],
] as [ShortcutModifiers])
func `command with control or option, or no command at all, is not an app's command`(modifiers: ShortcutModifiers) {
    for keyCode in commandKeys {
        #expect(!GlobalShortcut.isAppCommand(keyCode: keyCode, modifiers: modifiers), "key \(keyCode)")
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: modifiers)?.modifiers == modifiers, "key \(keyCode)")
    }
}

@Test(arguments: [ShortcutModifiers(), .shift])
func `shift alone or no modifier is not an app's command, though it makes no shortcut either`(
    modifiers: ShortcutModifiers,
) {
    for keyCode in commandKeys + [49, 111] {
        #expect(!GlobalShortcut.isAppCommand(keyCode: keyCode, modifiers: modifiers), "key \(keyCode)")
        #expect(GlobalShortcut(keyCode: keyCode, modifiers: modifiers) == nil, "key \(keyCode)")
    }
}

@Test func `option space is a shortcut and the command bar's default`() {
    #expect(GlobalShortcut(keyCode: 49, modifiers: .option) == .commandBar)
}

@Test func `a remembered app's command falls back, and a remembered command F12 is kept`() throws {
    let command = ShortcutModifiers.command.rawValue
    #expect(GlobalShortcut.remembered(keyCode: 13, modifiers: command, fallback: .commandBar) == .commandBar)
    #expect(GlobalShortcut.remembered(keyCode: 12, modifiers: command | 4, fallback: .commandBar) == .commandBar)
    let commandF12 = try #require(GlobalShortcut(keyCode: f12, modifiers: .command))
    #expect(GlobalShortcut.remembered(keyCode: f12, modifiers: command, fallback: .commandBar) == commandF12)
}
