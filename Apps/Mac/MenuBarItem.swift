import AppKit
import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The menu bar item: the state of the timer, drawn as one image.
struct MenuBarItemLabel: View {
    let countdown: Countdown

    var body: some View {
        Image(nsImage: MenuBarImage.image(for: countdown.label))
    }
}

/// Draws a ``MenuBarLabel`` as the item's image.
///
/// `MenuBarExtra` turns a `Text` label into a plain title and drops its font,
/// so tabular figures, which keep the item's width steady as the digits
/// change, survive only in an image. A template image is drawn in one color,
/// which would lose the workspace's dot, so this image is not a template.
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
        let width = ceil(symbolSize.width + (text.isEmpty ? 0 : gap + textSize.width))

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
            return true
        }
        // What VoiceOver reads, since the image is all the item shows.
        image.accessibilityDescription = parts.spoken
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

/// The timer's state for the menu bar, renewed exactly when what it shows changes.
///
/// Each tick settles the timer engine, so a block whose time is up closes and
/// the item returns to the outline dot. A `TimelineView` in a `MenuBarExtra`
/// label keeps the main thread busy updating the item from launch on, so the
/// label ticks on a timer instead.
@MainActor
@Observable
final class Countdown {
    private(set) var label = MenuBarLabel.idle(untracked: nil)

    private let context: ModelContext?
    private let appStart: Date
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "countdown")

    /// A countdown over the store in `container`, or the outline dot alone
    /// when there is no store. With `fixedTime` it is computed once for that
    /// instant and never ticks.
    init(container: ModelContainer?, fixedTime: Date?) {
        context = container?.mainContext
        appStart = fixedTime ?? .now
        let next = refresh(at: appStart)
        guard fixedTime == nil, context != nil else { return }

        let timer = Timer(fire: next, interval: MenuBarLabel.untrackedThreshold, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The schedule runs on a clock that stops while the Mac sleeps,
                // so every tick sets the next one from the wall clock again.
                self.timer?.fireDate = self.refresh(at: .now)
            }
        }
        // Common modes, so it keeps ticking while the menu is open. The
        // countdown lives as long as the app, so the timer is never invalidated.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.timer?.fireDate = self.refresh(at: .now)
            }
        }
    }

    /// Settles the timer at `now`, updates ``label``, and returns when to refresh next.
    @discardableResult
    private func refresh(at now: Date) -> Date {
        guard let context else {
            label = .idle(untracked: nil)
            return now.addingTimeInterval(MenuBarLabel.untrackedThreshold)
        }
        do {
            let engine = TimerEngine(context: context)
            let status = try engine.settle(at: now)
            let since = try MenuBarLabel.untrackedStart(
                in: context, appStart: appStart, now: now, calendar: .current,
            )
            let workspace = try engine.runningWorkspace()
            label = MenuBarLabel(status: status, workspace: workspace, untrackedSince: since, at: now)
            return MenuBarLabel.nextRedraw(status: status, untrackedSince: since, after: now)
        } catch {
            log.error("The timer could not be read: \(error.localizedDescription)")
            label = .idle(untracked: nil)
            return now.addingTimeInterval(60)
        }
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
