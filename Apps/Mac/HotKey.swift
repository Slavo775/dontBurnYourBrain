import Carbon
import DontBurnCore
import Foundation
import os

/// Why a global shortcut was not registered. Nothing was taken.
enum HotKeyProblem: Error, Equatable {
    /// Another app holds it exclusively, such as the other build of this app.
    case inUse
    /// macOS keeps it for one of its own shortcuts, or refuses it.
    case notAllowed

    /// The one line Settings shows.
    var message: String {
        switch self {
        case .inUse: String(localized: "Another app already uses this shortcut.")
        case .notAllowed: String(localized: "macOS doesn't allow this shortcut.")
        }
    }
}

/// Registers one global shortcut with the system and calls back when it is pressed.
@MainActor
protocol HotKeyRegistering: AnyObject {
    /// Registers `shortcut` in place of any registered before, and calls
    /// `onPress` on each press. Throws when the system refuses it, and then
    /// nothing is registered.
    func register(_ shortcut: GlobalShortcut, onPress: @escaping @MainActor () -> Void) throws(HotKeyProblem)
    /// Unregisters the shortcut, if one is registered.
    func unregister()
}

/// A global shortcut through Carbon's `RegisterEventHotKey`, which needs no
/// permission: no Accessibility and no Input Monitoring, because it reads no
/// other key.
///
/// It registers exclusively, so a second app that asks for the same shortcut
/// exclusively is refused, and so is this one when another app holds it so.
/// An app that registered without asking for that cannot be seen, and both
/// then hold it. A shortcut macOS uses itself, such as ⌘ Space for Spotlight,
/// is refused before it is registered. Each register, unregister and refusal
/// is logged in one line.
///
/// ponytail: the press handler takes every hot key of the app, which is right
/// while this is the only one. A second hot key needs an id check in the handler.
@MainActor
final class CarbonHotKey: HotKeyRegistering {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "shortcut")

    // The app keeps its one instance until it quits, so there is no deinit
    // that removes the handler, which points at this instance unretained.

    func register(_ shortcut: GlobalShortcut, onPress: @escaping @MainActor () -> Void) throws(HotKeyProblem) {
        unregister()
        let name = shortcut.displayName
        if Self.isUsedByMacOS(shortcut) {
            log.info("The command bar's shortcut \(name, privacy: .public) was not registered: macOS uses it")
            throw .notAllowed
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
            EventHotKeyID(signature: 0x4442_5942, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &reference,
        )
        guard status == noErr, let reference else {
            log.info("The command bar's shortcut \(name, privacy: .public) was not registered: status \(status)")
            throw status == eventHotKeyExistsErr ? .inUse : .notAllowed
        }
        hotKey = reference
        self.onPress = onPress
        installHandler()
        log.info("Registered the command bar's shortcut \(name, privacy: .public)")
    }

    func unregister() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
        guard let hotKey else { return }
        UnregisterEventHotKey(hotKey)
        self.hotKey = nil
        onPress = nil
        log.info("Unregistered the command bar's shortcut")
    }

    private func installHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<CarbonHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon calls the application target's handlers on the main thread.
            MainActor.assumeIsolated { hotKey.onPress?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            log.error("The shortcut's press handler could not be installed: status \(status)")
        }
    }

    /// Carbon's modifier mask for `modifiers`.
    private static func carbonModifiers(_ modifiers: GlobalShortcut.Modifiers) -> UInt32 {
        let masks: [(GlobalShortcut.Modifiers, Int)] = [
            (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
        ]
        return UInt32(masks.filter { modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 })
    }

    /// Whether `shortcut` is one of macOS's own enabled shortcuts, such as
    /// Spotlight's or the input source's, which only reads the list.
    private static func isUsedByMacOS(_ shortcut: GlobalShortcut) -> Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let entries = list?.takeRetainedValue() as? [[String: Any]]
        else { return false }
        let modifiers = Int(carbonModifiers(shortcut.modifiers))
        let mask = controlKey | optionKey | shiftKey | cmdKey
        return entries.contains { entry in
            entry[kHISymbolicHotKeyEnabled as String] as? Bool == true
                && entry[kHISymbolicHotKeyCode as String] as? Int == shortcut.keyCode
                && (entry[kHISymbolicHotKeyModifiers as String] as? Int).map { $0 & mask } == modifiers
        }
    }
}
