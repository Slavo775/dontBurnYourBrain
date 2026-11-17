import SwiftUI

/// The menu bar label: the current time with seconds, in the user's format.
struct ClockLabel: View {
    let ticker: Ticker

    var body: some View {
        Image(nsImage: image)
    }

    /// The time drawn as a template image, which the menu bar tints like text.
    ///
    /// `MenuBarExtra` turns a `Text` label into a plain title and drops its
    /// font, so tabular figures, which keep the item's width steady as the
    /// digits change, survive only in an image.
    private var image: NSImage {
        let time = ticker.now.formatted(.dateTime.hour().minute().second())
        let renderer = ImageRenderer(content: Text(verbatim: time).monospacedDigit())
        // Sharp on Retina displays. Others scale it down.
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        // What VoiceOver reads, since the image is all the item shows.
        image.accessibilityDescription = time
        return image
    }
}

/// The current time, renewed on every whole second, or a fixed instant that never changes.
///
/// A `TimelineView` in a `MenuBarExtra` label keeps the main thread busy
/// updating the item from launch on, so the label ticks on a timer instead.
@MainActor
@Observable
final class Ticker {
    private(set) var now: Date

    init(fixedTime: Date?) {
        now = fixedTime ?? .now
        guard fixedTime == nil else { return }
        let timer = Timer(fire: Self.nextSecond(after: now), interval: 1, repeats: true) { [weak self] timer in
            let now = Date.now
            // The schedule runs on a clock that stops while the Mac sleeps,
            // so every tick lines up with the next whole second again.
            timer.fireDate = Self.nextSecond(after: now)
            MainActor.assumeIsolated { self?.now = now }
        }
        // Common modes, so it keeps ticking while the menu is open. The ticker
        // lives as long as the app, so the timer is never invalidated.
        RunLoop.main.add(timer, forMode: .common)
    }

    private nonisolated static func nextSecond(after date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down) + 1)
    }
}

#Preview {
    // 2026-01-15 08:41:30 UTC.
    ClockLabel(ticker: Ticker(fixedTime: Date(timeIntervalSince1970: 1_768_466_490)))
}
