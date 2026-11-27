import AppKit
import DontBurnCore
import SwiftUI

/// What the open command bar holds: the typed text, the results it gives,
/// and which one Return takes.
@MainActor
@Observable
final class CommandBarModel {
    /// The typed text. A change selects the first result again.
    var text = "" {
        didSet {
            if text != oldValue {
                selection = 0
                failedSelection = nil
            }
        }
    }

    /// The result Return takes, counted from 0.
    private(set) var selection = 0

    /// The result that was taken but that the timer refused, or `nil`.
    var failedSelection: Int?

    let countdown: Countdown

    init(countdown: Countdown) {
        self.countdown = countdown
    }

    /// The rows for the typed text, with the timer as it is now.
    var results: [BarResult] {
        BarCommand.commands(for: text, in: countdown.workspaces).map {
            $0.result(
                in: countdown.state,
                dueBreakMinutes: countdown.panel?.dueBreakMinutes,
                lastBreakMinutes: countdown.breakMinutes,
            )
        }
    }

    /// The workspaces that 1 to 3 start with the field empty, in their order.
    var quickStarts: ArraySlice<Workspace> {
        countdown.workspaces.prefix(WorkspaceRoster.menuStartCount)
    }

    /// Empties the field for the next opening.
    func clear() {
        text = ""
        selection = 0
        failedSelection = nil
    }

    /// Moves the selection by `step` rows, within the results.
    func moveSelection(by step: Int) {
        selection = min(max(selection + step, 0), max(results.count - 1, 0))
    }
}

/// The command bar: a borderless, non-activating panel in the middle of the
/// screen with the mouse, opened by the global shortcut or from the menu.
///
/// It becomes key so the field takes typing at once, without bringing the
/// app forward, so when it closes the keys go back to the app the owner was
/// in. It closes on Escape, on the shortcut, when it loses focus, and after
/// an action was taken. Opening it takes the focus from the compact panel,
/// which then closes, and the other way round.
@MainActor
final class CommandBarController: NSObject, NSWindowDelegate {
    /// The global shortcut that opens and closes the bar.
    let shortcut: CommandBarShortcut

    private let countdown: Countdown
    private let model: CommandBarModel
    /// The bar's view, kept while it is closed, so its field is there to take the focus when it opens.
    private lazy var content = NSHostingView(rootView: CommandBarView(model: model) { [weak self] in self?.take($0) })
    /// Where the bar's top edge stays while its results grow and shrink.
    private var top: CGFloat = 0

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
        panel.contentView = content
        panel.delegate = self
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        return panel
    }()

    /// A bar over `countdown`, opened by `shortcut`, which it registers now
    /// when it is on.
    init(countdown: Countdown, shortcut: CommandBarShortcut) {
        self.countdown = countdown
        self.shortcut = shortcut
        model = CommandBarModel(countdown: countdown)
        super.init()
        shortcut.onPress = { [weak self] in self?.toggle() }
        shortcut.apply()
    }

    /// Opens the bar, or closes it when it is open.
    func toggle() {
        if panel.isVisible {
            close()
        } else {
            open()
        }
    }

    /// Opens the bar once the menu that asks for it has closed. A menu
    /// still tracking takes the focus back when it closes, and the bar,
    /// which closes when it loses focus, would close with it.
    func openAfterMenu() {
        perform(#selector(openFromMenu), with: nil, afterDelay: 0)
    }

    @objc private func openFromMenu() {
        open()
    }

    /// Opens the bar with an empty field, ready for typing.
    func open() {
        // Settle first, so the results fit the timer now.
        countdown.reschedule()
        model.clear()
        panel.setContentSize(content.fittingSize)
        place()
        panel.makeKeyAndOrderFront(nil)
        // At once, so the first letters typed right after the shortcut reach
        // the field. SwiftUI's focus would come a pass later and lose them.
        content.layoutSubtreeIfNeeded()
        if let field = content.firstTextField() {
            panel.makeFirstResponder(field)
        }
    }

    private func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Centres the bar on the screen with the mouse, its top a fifth of the way down, as Spotlight sits.
    private func place() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        top = visible.maxY - visible.height / 5
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: top - size.height))
    }

    /// Escape closes, ↑ and ↓ move the selection, and Return or the keypad's
    /// Enter takes it. With the field empty, 1 to 3 start the first three
    /// workspaces at once. Every other key types. Returns whether the key was used.
    ///
    /// A held key acts once, as in the panel.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            close()
        case 126:
            model.moveSelection(by: -1)
        case 125:
            model.moveSelection(by: 1)
        case 36, 76:
            if !event.isARepeat {
                take(model.selection)
            }
        default:
            return startQuick(event)
        }
        return true
    }

    /// 1 to 3 with the field empty and no ⌘, ⌃ or ⌥.
    private func startQuick(_ event: NSEvent) -> Bool {
        guard model.text.isEmpty, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let key = event.characters.flatMap({ Int($0) }), model.quickStarts.indices.contains(key - 1)
        else { return false }
        if !event.isARepeat {
            countdown.start(model.quickStarts[key - 1])
            if !countdown.lastStepFailed {
                close()
            }
        }
        return true
    }

    /// Takes the result at `index`. One that is refused stays, with its reason.
    private func take(_ index: Int) {
        guard model.results.indices.contains(index) else { return }
        let result = model.results[index]
        guard result.refusal == nil else { return }
        if perform(result.action) {
            close()
        } else {
            model.failedSelection = index
        }
    }

    /// Takes `action` on the countdown, as the panel's buttons do, and returns whether it was taken.
    private func perform(_ action: BarAction) -> Bool {
        switch action {
        case let .start(workspace, minutes):
            countdown.start(workspace, minutes: minutes, presetID: workspace.focusPreset?.id)
        case .pause, .resume: countdown.perform(.pauseOrResume)
        case let .startBreak(minutes): countdown.startBreak(minutes: minutes)
        case let .plannedBreak(minutes): countdown.startPlannedBreak(minutes: minutes)
        case .endBreak: countdown.perform(.breakOrEndBreak)
        case .extend: countdown.perform(.extend)
        case .endBlock: countdown.endBlock()
        }
        return !countdown.lastStepFailed
    }

    // MARK: - NSWindowDelegate

    /// A click anywhere else, in this app or another, takes the key and closes the bar.
    func windowDidResignKey(_: Notification) {
        close()
    }

    func windowDidResize(_: Notification) {
        // The bar grows downwards as results come and go.
        guard panel.isVisible else { return }
        panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
        panel.invalidateShadow()
    }
}

private extension NSView {
    /// The first editable text field among the subviews, depth first.
    func firstTextField() -> NSTextField? {
        for view in subviews {
            if let field = view as? NSTextField, field.isEditable {
                return field
            }
            if let field = view.firstTextField() {
                return field
            }
        }
        return nil
    }
}
