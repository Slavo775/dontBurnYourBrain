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
    private let mainWindow: MainWindowController
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

    private lazy var menu = NSHostingMenu(rootView: StatusItemMenu(countdown: countdown) { [weak self] in
        self?.mainWindow.show()
    })

    init(countdown: Countdown, mainWindow: MainWindowController) {
        self.countdown = countdown
        self.mainWindow = mainWindow
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // On the cell: the element the menu bar shows for the item reads the cell's actions, not the button's.
            button.cell?.setAccessibilityCustomActions([NSAccessibilityCustomAction(
                name: String(localized: "Show menu"), target: self, selector: #selector(showMenuFromAccessibility),
            )])
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

    /// Opens the right-click menu for VoiceOver and other accessibility
    /// clients, whose `AXPress` on the item opens the panel instead.
    ///
    /// The menu tracks until it closes, so it opens on the next pass of the
    /// run loop, and the client's request returns at once.
    @objc private func showMenuFromAccessibility() -> Bool {
        closePanel()
        DispatchQueue.main.async { [weak self] in self?.showMenu() }
        return true
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

    /// While a block runs: P pauses and resumes, B opens "Break for" while
    /// working and ends a break, + adds 15 minutes, S switches and E ends the
    /// block. On a break with nothing running, B ends it, + lengthens it and S
    /// switches. In a list of workspaces, 1 to 9 start the workspace on that
    /// key. In "Break for", 1 to 4 start a break of that length, and Return or
    /// the keypad's Enter the preselected one. With nothing running, B opens
    /// "Break for", and ⌘N the custom block form, where Return starts and
    /// Escape goes back. Elsewhere Escape closes. ⌘O closes the panel and
    /// opens the window. Returns whether the key was used.
    ///
    /// A held key acts once. Repeats would extend again and again, pause and
    /// resume into near-empty entries, or start block after block.
    private func handleKey(_ event: NSEvent) -> Bool {
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
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "o" {
            if !event.isARepeat {
                closePanel()
                mainWindow.show()
            }
            return true
        }
        guard modifiers.isEmpty else { return false }
        return handlePlainKey(event)
    }

    /// A key without ⌘, ⌃ or ⌥, on the page the panel shows.
    private func handlePlainKey(_ event: NSEvent) -> Bool {
        let isIdle = countdown.panel == nil
        if navigation.page == .breakLength {
            return startBreak(event)
        }
        if isIdle, navigation.page == .customBlock {
            return startCustomBlock(event)
        }
        if isIdle, countdown.hasStore, event.characters?.lowercased() == "b" {
            if !event.isARepeat {
                navigation.page = .breakLength
            }
            return true
        }
        if isIdle || navigation.page == .switching {
            return quickStart(event)
        }
        return takeQuickAction(event)
    }

    /// ⌘N, only with nothing running, outside "Break for", and a workspace to start.
    private func openCustomBlock(_ event: NSEvent) -> Bool {
        guard countdown.panel == nil, navigation.page != .customBlock, navigation.page != .breakLength,
              !countdown.workspaces.isEmpty
        else {
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

    /// 1 to 4, Return or the keypad's Enter, in "Break for".
    private func startBreak(_ event: NSEvent) -> Bool {
        let minutes: Int
        if event.keyCode == 36 || event.keyCode == 76 {
            minutes = countdown.breakMinutes
        } else if let key = event.characters.flatMap({ Int($0) }), let length = TimerEngine.breakLength(onKey: key) {
            minutes = length
        } else {
            return false
        }
        if !event.isARepeat {
            navigation.startBreak(minutes: minutes, with: countdown)
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

    /// P, B, +, S and E, while a block or a break runs.
    private func takeQuickAction(_ event: NSEvent) -> Bool {
        guard let state = countdown.panel?.state, let key = event.characters?.lowercased(),
              ["p", "b", "+", "s", "e"].contains(key)
        else { return false }
        if !event.isARepeat {
            takeQuickAction(key, in: state)
        }
        return true
    }

    /// One of P, B, +, S and E in `state`. One the state does not offer does nothing.
    private func takeQuickAction(_ key: String, in state: TimerState) {
        let action: QuickAction
        switch key {
        case "p": action = .pauseOrResume
        case "b" where QuickAction.canStartBreak(in: state):
            navigation.page = .breakLength
            return
        case "b": action = .breakOrEndBreak
        case "+": action = .extend
        case "s" where !countdown.workspaces.isEmpty:
            navigation.page = .switching
            return
        case "e" where state.hasBlock:
            countdown.endBlock()
            return
        default: return
        }
        if action.isAvailable(in: state) {
            countdown.perform(action)
        }
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

/// The right-click menu: the timer's actions while a block or a break runs,
/// or "Take a break" while nothing runs, then the first three workspaces to
/// start, then the window, Settings and Quit.
struct StatusItemMenu: View {
    let countdown: Countdown
    let openWindow: () -> Void

    var body: some View {
        let state = countdown.state
        if state != .idle {
            if QuickAction.pauseOrResume.isAvailable(in: state) {
                Button(state == .paused ? "Resume" : "Pause") {
                    countdown.perform(.pauseOrResume)
                }
            }
            if state.isBreak {
                Button("End break") {
                    countdown.perform(.breakOrEndBreak)
                }
            } else {
                BreakLengthMenu(countdown: countdown)
                    .disabled(!QuickAction.canStartBreak(in: state))
            }
            Button("Add 15 minutes") {
                countdown.perform(.extend)
            }
            if state.hasBlock {
                Button("End block") {
                    countdown.endBlock()
                }
            }
            Divider()
        } else if countdown.hasStore {
            BreakLengthMenu(countdown: countdown)
            Divider()
        }
        let starts = countdown.workspaces.prefix(WorkspaceRoster.menuStartCount)
        if !starts.isEmpty {
            // While a block runs, a start acts as a switch.
            ForEach(starts) { workspace in
                Button("Start \(workspace.name) for \(blockLength(workspace.defaultBlockMinutes))") {
                    countdown.start(workspace)
                }
            }
            Divider()
        }
        Button("Open the window", action: openWindow)
            .keyboardShortcut("o")
        OpenSettingsButton()
        Divider()
        Button("Quit \(Bundle.main.displayName)") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// "Take a break", a submenu with the break's lengths.
private struct BreakLengthMenu: View {
    let countdown: Countdown

    var body: some View {
        Menu("Take a break") {
            ForEach(TimerEngine.breakLengthChoices, id: \.self) { minutes in
                Button("\(minutes) min") {
                    countdown.startBreak(minutes: minutes)
                }
            }
        }
    }
}
