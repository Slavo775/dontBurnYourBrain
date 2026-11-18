import AppKit
import DontBurnCore
import SwiftUI

/// The menu bar item: a click toggles the compact panel under it, a
/// right-click or a Control-click opens the menu.
///
/// `MenuBarExtra` offers one or the other, so the item is an `NSStatusItem`.
/// The panel is a borderless, non-activating `NSPanel`: it becomes key so its
/// keys work at once, without making the app frontmost, and it can have the
/// panel's own background and corners, which an `NSPopover` cannot.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let countdown: Countdown
    private let navigation = PanelNavigation()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private lazy var panel: KeyPanel = {
        let panel = KeyPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true,
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // The app is never active, so a panel that hides on deactivation would never show.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: CompactPanelView(countdown: countdown, navigation: navigation))
        panel.delegate = self
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        return panel
    }()

    private lazy var menu = NSHostingMenu(rootView: StatusItemMenu(countdown: countdown))

    init(countdown: Countdown) {
        self.countdown = countdown
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        show(countdown.label)
        countdown.onLabelChange = { [weak self] in self?.show($0) }
    }

    private func show(_ label: MenuBarLabel) {
        let image = MenuBarImage.image(for: label)
        statusItem.button?.image = image
        statusItem.button?.setAccessibilityTitle(image.accessibilityDescription)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            closePanel()
            showMenu()
        } else if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func showMenu() {
        // Settle first, so the menu offers what fits the timer now.
        countdown.reschedule()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // A menu left on the item would open on every left click too.
        statusItem.menu = nil
    }

    private func openPanel() {
        navigation.isSwitching = false
        countdown.isPanelOpen = true
        if let content = panel.contentView {
            panel.setContentSize(content.fittingSize)
        }
        placePanel()
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        countdown.isPanelOpen = false
    }

    /// Puts the panel's top edge just under the item, inside the screen.
    private func placePanel() {
        guard let itemFrame = statusItem.button?.window?.frame else { return }
        let size = panel.frame.size
        let screen = statusItem.button?.window?.screen?.visibleFrame ?? itemFrame
        let margin: CGFloat = 8
        let left = min(max(itemFrame.minX, screen.minX + margin), screen.maxX - size.width - margin)
        let top = min(itemFrame.minY, screen.maxY) - 6
        panel.setFrameOrigin(NSPoint(x: left, y: top - size.height))
    }

    /// P pauses and resumes, B takes and ends a break, + adds 15 minutes, S
    /// switches, and Escape closes. Returns whether the key was used.
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            closePanel()
            return true
        }
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let state = countdown.panel?.state, !navigation.isSwitching
        else { return false }
        let action: QuickAction
        switch event.characters?.lowercased() {
        case "p": action = .pauseOrResume
        case "b": action = .breakOrEndBreak
        case "+": action = .extend
        case "s":
            if !event.isARepeat {
                navigation.isSwitching = true
            }
            return true
        default: return false
        }
        // A held key acts once. Repeats would extend again and again, or
        // pause and resume into near-empty entries.
        if !event.isARepeat, action.isAvailable(in: state) {
            countdown.perform(action)
        }
        return true
    }

    // MARK: - NSWindowDelegate

    /// A click anywhere else, in this app or another, takes the key and closes the panel.
    func windowDidResignKey(_: Notification) {
        closePanel()
    }

    func windowDidResize(_: Notification) {
        // The panel grows downwards when its view changes, such as to "Switch to".
        guard panel.isVisible else { return }
        placePanel()
        panel.invalidateShadow()
    }
}

/// A borderless panel that can become key and hands key presses to `onKey` first.
private final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

/// The right-click menu: the timer's actions while a block runs, then Settings and Quit.
struct StatusItemMenu: View {
    let countdown: Countdown

    var body: some View {
        let state = countdown.state
        if state != .idle {
            Button(state == .paused ? "Resume" : "Pause") {
                countdown.perform(.pauseOrResume)
            }
            Button(state == .onBreak ? "End break" : "Take a break") {
                countdown.perform(.breakOrEndBreak)
            }
            .disabled(!QuickAction.breakOrEndBreak.isAvailable(in: state))
            Button("Add 15 minutes") {
                countdown.perform(.extend)
            }
            Button("End block") {
                countdown.endBlock()
            }
            Divider()
        }
        OpenSettingsButton()
        Divider()
        Button("Quit \(Bundle.main.displayName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
