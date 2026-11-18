import AppKit
import DontBurnCore
import os
import SwiftData
import SwiftUI

/// Draws a ``MenuBarLabel`` as the item's image.
///
/// One image keeps the dot, the name and the digits together, in tabular
/// figures that keep the item's width steady as the digits change. (Under
/// `MenuBarExtra`, a `Text` label lost its font, so an image was the only
/// way.) A template image is drawn in one color, which would lose the
/// workspace's dot, so this image is not a template.
/// Instead it is drawn by a handler that runs each time the item is drawn,
/// under the menu bar's own appearance: the text and the outline take the
/// label color of that appearance, and the dot the workspace color's light or
/// dark value, on every display.
///
/// Sizes follow the prototype's menu bar tiles: a 10 pt dot, 6 pt to the
/// text, and text at weight 500.
enum MenuBarImage {
    private static var font: NSFont {
        .monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .medium)
    }

    private static let dotDiameter: CGFloat = 10
    private static let gap: CGFloat = 6
    private static let cupPointSize: CGFloat = 11
    /// The widest a name may be drawn. Sixteen characters fit in ordinary
    /// letters, and a name of wide letters is cut here, so the item never
    /// crowds the menu bar on a notched display.
    private static let maximumNameWidth: CGFloat = 116

    /// "DEV" after the label in the Dev build, so it is never taken for the
    /// daily copy. Small and in the secondary color, so the item stays narrow.
    private static let marker: String? = BuildVariant.current == .dev ? String(localized: "DEV") : nil
    private static var markerFont: NSFont {
        .systemFont(ofSize: 9, weight: .bold)
    }

    private static let markerGap: CGFloat = 4

    /// The marker's width with the gap before it, or 0 without a marker.
    private static var markerWidth: CGFloat {
        guard let marker else { return 0 }
        return markerGap + (marker as NSString).size(withAttributes: [.font: markerFont]).width
    }

    /// Draws the marker `markerGap` after `left`, centered in `height`.
    private static func drawMarker(after left: CGFloat, height: CGFloat) {
        guard let marker else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont, .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = (marker as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: left + markerGap, y: (height - size.height) / 2)
        (marker as NSString).draw(at: origin, withAttributes: attributes)
    }

    private enum Symbol {
        case dot(WorkspaceColor)
        case outline
        case cup
    }

    static func image(for label: MenuBarLabel) -> NSImage {
        let font = font
        let parts = parts(of: label, font: font)
        let symbol = parts.symbol, text = parts.text
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = text.isEmpty ? .zero : (text as NSString).size(withAttributes: attributes)
        // The prototype's cup is drawn in outline, with steam above it.
        let cup = NSImage(systemSymbolName: "cup.and.heat.waves", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: cupPointSize, weight: .medium))
        let symbolSize = switch symbol {
        case .cup: cup?.size ?? .zero
        case .dot, .outline: NSSize(width: dotDiameter, height: dotDiameter)
        }
        let height = ceil(max(textSize.height, symbolSize.height))
        let labelWidth = symbolSize.width + (text.isEmpty ? 0 : gap + textSize.width)
        let width = ceil(labelWidth + markerWidth)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // Resolved here, while the item is drawn, so it follows the menu bar.
            let ink = NSColor.labelColor
            let symbolRect = NSRect(
                x: 0, y: (height - symbolSize.height) / 2,
                width: symbolSize.width, height: symbolSize.height,
            )
            switch symbol {
            case let .dot(color):
                color.nsColor.setFill()
                NSBezierPath(ovalIn: symbolRect).fill()
            case .outline:
                ink.setStroke()
                let path = NSBezierPath(ovalIn: symbolRect.insetBy(dx: 0.75, dy: 0.75))
                path.lineWidth = 1.5
                path.stroke()
            case .cup:
                // The symbol is drawn in black, then tinted where it has ink.
                cup?.draw(in: symbolRect)
                ink.setFill()
                symbolRect.fill(using: .sourceAtop)
            }
            if !text.isEmpty {
                var textAttributes = attributes
                textAttributes[.foregroundColor] = ink
                (text as NSString).draw(
                    at: NSPoint(x: symbolSize.width + gap, y: (height - textSize.height) / 2),
                    withAttributes: textAttributes,
                )
            }
            drawMarker(after: labelWidth, height: height)
            return true
        }
        // What VoiceOver reads, since the image is all the item shows.
        image.accessibilityDescription = marker == nil ? parts.spoken : String(localized: "\(parts.spoken), Dev build")
        return image
    }

    /// The symbol, the text shown, and the text VoiceOver reads.
    private struct Parts {
        let symbol: Symbol
        let text: String
        let spoken: String

        init(_ symbol: Symbol, _ text: String, _ spoken: String) {
            self.symbol = symbol
            self.text = text
            self.spoken = spoken
        }
    }

    private static func parts(of label: MenuBarLabel, font: NSFont) -> Parts {
        switch label {
        case let .running(name, color, time):
            let shown = fitted(name, font: font)
            return Parts(
                .dot(color),
                shown.isEmpty ? time : "\(shown) \(time)",
                name.isEmpty ? time : "\(name) \(time)",
            )
        case let .paused(name, color):
            let shown = fitted(name, font: font)
            return Parts(
                .dot(color),
                shown.isEmpty ? String(localized: "paused") : String(localized: "\(shown), paused"),
                name.isEmpty ? String(localized: "paused") : String(localized: "\(name), paused"),
            )
        case let .onBreak(time?):
            return Parts(.cup, time, String(localized: "On a break, \(time) left"))
        case .onBreak(nil):
            return Parts(.cup, "", String(localized: "On a break"))
        case let .idle(untracked?):
            return Parts(.outline, untracked, String(localized: "Nothing running, \(untracked) untracked"))
        case .idle(nil):
            return Parts(.outline, "", String(localized: "Nothing running"))
        }
    }

    /// `name` cut at the end until it fits ``maximumNameWidth``.
    private static func fitted(_ name: String, font: NSFont) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: attributes).width
        }
        guard width(name) > maximumNameWidth else { return name }
        var kept = name.hasSuffix("…") ? String(name.dropLast()) : name
        while !kept.isEmpty, width(kept + "…") > maximumNameWidth {
            kept = String(kept.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return kept + "…"
    }
}

/// The timer's state for the menu bar item and the panel, renewed exactly
/// when what they show changes, and the one way the interface acts on the timer.
///
/// Each tick settles the timer engine, so a block whose time is up closes and
/// the item returns to the outline dot. The item and the panel read the same
/// settled state. While the panel is open the countdown ticks every second,
/// and otherwise only as often as the item needs. A `TimelineView` in a menu
/// bar label kept the main thread busy updating the item from launch on, so
/// the countdown ticks on a timer instead.
@MainActor
@Observable
final class Countdown {
    private(set) var label = MenuBarLabel.idle(untracked: nil) {
        didSet {
            if label != oldValue {
                onLabelChange?(label)
            }
        }
    }

    /// What the panel shows, or `nil` when nothing runs or there is no store.
    private(set) var panel: CompactPanel?

    /// The workspaces to start or switch to, in their order. Empty without a store.
    ///
    /// Stored and renewed on every refresh, so the panel follows a new order
    /// or an archived workspace from Settings each time it opens.
    private(set) var workspaces: [Workspace] = []

    /// Today's tracked time, such as `0:10`, or `nil` without a store.
    private(set) var trackedToday: String?

    /// Whether the panel is open. While it is, the countdown ticks every second.
    var isPanelOpen = false {
        didSet {
            if isPanelOpen != oldValue {
                reschedule()
            }
        }
    }

    /// Called with the new label each time it changes.
    @ObservationIgnored var onLabelChange: ((MenuBarLabel) -> Void)?

    /// The sounds and the notifications, or `nil` when the countdown is frozen.
    let alerts: AlertCenter?

    private let context: ModelContext?
    private let appStart: Date
    private let fixedTime: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?
    /// The status the last settle reported, and when. `nil` after a user's
    /// action, so only a block or a break that runs out by itself plays a sound.
    @ObservationIgnored private var settled: (status: TimerStatus, at: Date)?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "countdown")

    /// A countdown over the store in `container`, or the outline dot alone
    /// when there is no store. With `fixedTime` it is computed for that
    /// instant, acts at that instant, never ticks and gives no alerts.
    init(container: ModelContainer?, fixedTime: Date?, alerts: AlertCenter? = nil) {
        context = container?.mainContext
        self.fixedTime = fixedTime
        self.alerts = fixedTime == nil ? alerts : nil
        appStart = fixedTime ?? .now
        let next = refresh(at: appStart)
        guard fixedTime == nil, context != nil else { return }

        let timer = Timer(fire: next, interval: MenuBarLabel.untrackedThreshold, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // The schedule runs on a clock that stops while the Mac sleeps,
                // so every tick sets the next one from the wall clock again.
                self?.reschedule()
            }
        }
        // Common modes, so it keeps ticking while a menu is open. The
        // countdown lives as long as the app, so the timer is never invalidated.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reschedule()
            }
        }
        // A switch changed in Settings replans the notifications at once.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reschedule()
            }
        }
    }

    /// The timer's state, `.idle` when nothing runs or there is no store.
    var state: TimerState {
        panel?.state ?? .idle
    }

    /// Whether a store is open. Without one there is nothing to start.
    var hasStore: Bool {
        context != nil
    }

    /// Takes `action` on the running block now.
    func perform(_ action: QuickAction) {
        act("take a quick action") { try action.perform(with: $0, at: $1) }
    }

    /// Starts a block for `workspace` now, of `minutes` or its default length.
    /// Whatever runs ends first, so this also switches.
    func start(_ workspace: Workspace, minutes: Int? = nil) {
        act("start a block") { try $0.start(workspace, minutes: minutes, at: $1) }
        // The first start asks for the permission to notify, never the launch.
        alerts?.askPermissionIfUndetermined()
    }

    /// Ends the running block now.
    func endBlock() {
        act("end the block") { try $0.end(at: $1) }
    }

    /// Settles now, updates what the item and the panel show, and sets the next tick.
    func reschedule() {
        let next = refresh(at: fixedTime ?? .now)
        timer?.fireDate = next
    }

    private func act(_ what: String, _ body: (TimerEngine, Date) throws -> Void) {
        guard let context else { return }
        do {
            try body(TimerEngine(context: context), fixedTime ?? .now)
        } catch {
            log.error("Could not \(what): \(error.localizedDescription)")
        }
        settled = nil
        reschedule()
    }

    /// Settles the timer at `now`, updates ``label`` and ``panel``, and returns when to refresh next.
    @discardableResult
    private func refresh(at now: Date) -> Date {
        guard let context else {
            label = .idle(untracked: nil)
            panel = nil
            workspaces = []
            trackedToday = nil
            return now.addingTimeInterval(MenuBarLabel.untrackedThreshold)
        }
        do {
            let engine = TimerEngine(context: context)
            let status = try engine.settle(at: now)
            let since = try MenuBarLabel.untrackedStart(
                in: context, appStart: appStart, now: now, calendar: .current,
            )
            let block = try engine.runningBlock()
            announce(status, workspace: block?.workspace?.name ?? "", at: now)
            label = MenuBarLabel(status: status, workspace: block?.workspace, untrackedSince: since, at: now)
            let tracked = try CompactPanel.trackedToday(in: context, now: now, calendar: .current)
            panel = CompactPanel(status: status, block: block, tracked: tracked)
            trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
            workspaces = try WorkspaceRoster(context: context).activeWorkspaces()
            let next = MenuBarLabel.nextRedraw(status: status, untrackedSince: since, after: now)
            guard isPanelOpen, let tick = CompactPanel.nextRedraw(status: status, after: now) else { return next }
            return min(next, tick)
        } catch {
            log.error("The timer could not be read: \(error.localizedDescription)")
            settled = nil
            label = .idle(untracked: nil)
            panel = nil
            workspaces = []
            trackedToday = nil
            return now.addingTimeInterval(60)
        }
    }

    /// Plays the sound of an alert whose moment passed since the last settle,
    /// and replans the pending notifications.
    private func announce(_ status: TimerStatus, workspace: String, at now: Date) {
        defer { settled = (status, now) }
        guard let alerts else { return }
        if let settled, let kind = AlertKind.due(from: settled.status, at: settled.at, to: status, at: now) {
            alerts.play(kind)
        }
        alerts.schedule(PlannedAlert.plan(for: status, workspace: workspace, settings: alerts.settings, at: now))
    }
}

#Preview {
    VStack(alignment: .leading) {
        Image(nsImage: MenuBarImage.image(for: .running(name: "Acme", color: .teal, time: "1:24")))
        Image(nsImage: MenuBarImage.image(for: .running(name: "Globex", color: .indigo, time: "4:59")))
        Image(nsImage: MenuBarImage.image(for: .paused(name: "Personal", color: .ochre)))
        Image(nsImage: MenuBarImage.image(for: .onBreak(time: "4:12")))
        Image(nsImage: MenuBarImage.image(for: .idle(untracked: nil)))
        Image(nsImage: MenuBarImage.image(for: .idle(untracked: "0:15")))
    }
    .padding()
}
