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
        navigation.page = .main
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

    /// While a block runs: P pauses and resumes, B takes and ends a break, +
    /// adds 15 minutes and S switches. In a list of workspaces, 1 to 9 start
    /// the workspace on that key. With nothing running, ⌘N opens the custom
    /// block form, where Return starts and Escape goes back. Elsewhere Escape
    /// closes. Returns whether the key was used.
    ///
    /// A held key acts once. Repeats would extend again and again, pause and
    /// resume into near-empty entries, or start block after block.
    private func handleKey(_ event: NSEvent) -> Bool {
        let isIdle = countdown.panel == nil
        if event.keyCode == 53 {
            if navigation.page == .customBlock {
                navigation.page = .main
            } else {
                closePanel()
            }
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "n" {
            return openCustomBlock(event)
        }
        guard modifiers.isEmpty else { return false }
        if isIdle, navigation.page == .customBlock {
            return startCustomBlock(event)
        }
        if isIdle || navigation.page == .switching {
            return quickStart(event)
        }
        return takeQuickAction(event)
    }

    /// ⌘N, only with nothing running and a workspace to start.
    private func openCustomBlock(_ event: NSEvent) -> Bool {
        guard countdown.panel == nil, navigation.page != .customBlock, !countdown.workspaces.isEmpty else {
            return false
        }
        if !event.isARepeat {
            navigation.openCustomBlock(countdown.workspaces)
        }
        return true
    }

    /// Return or the keypad's Enter, in the custom block form.
    private func startCustomBlock(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false }
        if !event.isARepeat {
            navigation.startCustomBlock(with: countdown)
        }
        return true
    }

    /// 1 to 9, in a list of workspaces.
    private func quickStart(_ event: NSEvent) -> Bool {
        guard let key = event.characters.flatMap({ Int($0) }),
              let position = WorkspaceRoster.quickStartPosition(ofKey: key),
              countdown.workspaces.indices.contains(position)
        else { return false }
        if !event.isARepeat {
            navigation.page = .main
            countdown.start(countdown.workspaces[position])
        }
        return true
    }

    /// P, B, + and S, while a block runs.
    private func takeQuickAction(_ event: NSEvent) -> Bool {
        guard let state = countdown.panel?.state else { return false }
        let action: QuickAction
        switch event.characters?.lowercased() {
        case "p": action = .pauseOrResume
        case "b": action = .breakOrEndBreak
        case "+": action = .extend
        case "s":
            if !event.isARepeat {
                navigation.page = .switching
            }
            return true
        default: return false
        }
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

/// The right-click menu: the timer's actions while a block runs, or the first
/// three workspaces to start while nothing runs, then Settings and Quit.
struct StatusItemMenu: View {
    let countdown: Countdown

    var body: some View {
        let state = countdown.state
        let starts = countdown.workspaces.prefix(WorkspaceRoster.menuStartCount)
        if state == .idle, !starts.isEmpty {
            ForEach(starts) { workspace in
                Button("Start \(workspace.name) for \(blockLength(workspace.defaultBlockMinutes))") {
                    countdown.start(workspace)
                }
            }
            Divider()
        }
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
