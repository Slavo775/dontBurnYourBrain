import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The question about time away from the Mac, while it waits for an answer.
///
/// On a return after time away that a block counted as work, it notifies,
/// when notifications are allowed, and the question waits in the panel. It
/// never opens the panel. A second time away before the answer widens the
/// question. It lives in memory only, so a quit drops it, and the time counts
/// as worked. The countdown answers it and drops it when he acts on the timer.
@MainActor
@Observable
final class AwayQuestion {
    /// The time away that waits for an answer, or `nil`.
    private(set) var timeAway: TimeAway?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AwaySettings
    @ObservationIgnored private let alerts: AlertCenter?
    @ObservationIgnored private var watcher: AwayWatcher?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "away")

    /// A question over the store in `context`, as `settings` say, with
    /// `timeAway` waiting from the start, as in a scenario. Without
    /// `idleTime` it never notices time away by itself.
    init(
        context: ModelContext,
        settings: AwaySettings,
        alerts: AlertCenter?,
        idleTime: (any IdleTimeReading)?,
        timeAway: TimeAway?,
    ) {
        self.context = context
        self.settings = settings
        self.alerts = alerts
        self.timeAway = timeAway
        guard let idleTime else { return }
        let watcher = AwayWatcher(idleTime: idleTime) { TimeInterval(settings.thresholdMinutes) * 60 }
        watcher.onReturn = { [weak self] in self?.ask(since: $0, returnedAt: $1) }
        self.watcher = watcher
    }

    /// Follows the timer's `state`: time away is noticed while working, and
    /// nothing is asked while the switch is off.
    func follow(_ state: TimerState) {
        if !settings.asks {
            drop()
        }
        watcher?.isWatching = settings.asks && state == .working
    }

    /// Drops the question, so the time away counts as worked.
    func drop() {
        guard timeAway != nil else { return }
        timeAway = nil
        alerts?.withdrawAway()
    }

    private func ask(since lastInput: Date, returnedAt returned: Date) {
        guard settings.asks else { return }
        let threshold = TimeInterval(settings.thresholdMinutes) * 60
        do {
            guard let away = try TimerEngine(context: context)
                .timeAway(since: lastInput, returnedAt: returned, threshold: threshold)
            else { return }
            let question = timeAway?.widened(by: away) ?? away
            timeAway = question
            log.info("Asking about \(question.minutes) min away")
            alerts?.notifyAway(minutes: question.minutes)
        } catch {
            log.error("Could not read the time away: \(error.localizedDescription)")
        }
    }
}

/// The question about time away at the top of the panel: how long, and four
/// answers, drawn like a page such as "Break for": a title, then rows.
///
/// It waits on the panel's main page, while a block runs and after it ran out,
/// until he answers or acts on the timer. The rows are outlined, quieter than
/// the block's actions, and say what each answer does where a page shows a
/// key: the question has no keys of its own, so P, B, +, S and E keep acting
/// on the block. A line parts it from the block, as the footer's line does.
struct AwayQuestionView: View {
    let away: TimeAway
    let countdown: Countdown

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Away for \(blockLength(away.minutes))")
                    .font(.system(size: 15, weight: .semibold))
                Text("Was it work?")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Away for \(spokenLength). Was it work?")
            .accessibilityAddTraits(.isHeader)

            row("Work", effect: "nothing changes", answer: .work)
            row("Meeting", effect: "becomes a meeting", answer: .meeting)
            row("Break", effect: "becomes a break", answer: .break)
            row("Discard", effect: "cut out like a pause", answer: .discard)
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) {
            Color.line.frame(height: 1)
        }
    }

    /// One answer: its word, and what it does to the entries, muted, at the row's end.
    private func row(_ title: LocalizedStringKey, effect: LocalizedStringKey, answer: AwayAnswer) -> some View {
        Button {
            countdown.answer(answer)
        } label: {
            StartRow(key: nil, isGhost: true) {
                Text(title)
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(effect)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    /// The length for VoiceOver in words, such as "1 hour, 30 minutes", since "min" reads poorly.
    private var spokenLength: String {
        Duration.seconds(away.minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }
}
