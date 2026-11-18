import DontBurnCore
import SwiftData
import SwiftUI

/// Which view the panel shows. The panel's keys change it too, so it lives
/// outside the view.
@MainActor
@Observable
final class PanelNavigation {
    var isSwitching = false
}

/// The compact panel: the running block and its four quick actions, or the
/// list of workspaces to switch to.
struct CompactPanelView: View {
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let panel = countdown.panel {
                if navigation.isSwitching {
                    SwitchList(countdown: countdown, navigation: navigation)
                } else {
                    RunningBlock(panel: panel, countdown: countdown, navigation: navigation)
                }
                Footer(tracked: panel.trackedToday)
            } else {
                // The view for when nothing runs is card 14. Until then, a title alone.
                Text("Nothing running")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 36)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(width: 328, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: 16))
    }
}

/// The header, the countdown, the strip and the four quick actions.
private struct RunningBlock: View {
    let panel: CompactPanel
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        HStack(spacing: 10) {
            WorkspaceDot(color: panel.color)
            Text(panel.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
        }
        .frame(minHeight: 36)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(panel.clock)
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                Text(panel.seconds)
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .opacity(0.5)
            }
            .monospacedDigit()
            .opacity(panel.state == .paused ? 0.45 : 1)
            .accessibilityElement(children: .combine)

            Text(line)
                .foregroundStyle(Color.muted)

            ZStack {
                Color.sunken
                (panel.state == .onBreak ? Color.muted : panel.color.color)
                    .scaleEffect(x: panel.progress, anchor: .leading)
            }
            .frame(height: 8)
            .clipShape(.rect(cornerRadius: 4))
            .padding(.top, 6)
            .accessibilityHidden(true)
        }

        HStack(spacing: 8) {
            QuickButton(
                panel.state == .paused ? "Resume" : "Pause",
                symbol: panel.state == .paused ? "play.fill" : "pause.fill",
            ) {
                countdown.perform(.pauseOrResume)
            }
            QuickButton(panel.state == .onBreak ? "End break" : "Break", symbol: "cup.and.heat.waves") {
                countdown.perform(.breakOrEndBreak)
            }
            .disabled(!QuickAction.breakOrEndBreak.isAvailable(in: panel.state))
            Button {
                countdown.perform(.extend)
            } label: {
                VStack(spacing: 6) {
                    Text(verbatim: "+15")
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                    Text("min")
                }
            }
            .buttonStyle(QuickButtonStyle())
            .accessibilityLabel("Add 15 minutes")
            QuickButton("Switch", symbol: "arrow.left.arrow.right") {
                navigation.isSwitching = true
            }
        }
    }

    private var line: LocalizedStringKey {
        switch panel.line {
        case let .leftOf(length): "left of \(length)"
        case .paused: "Paused"
        case let .onBreak(name): "On a break, then back to \(name)"
        }
    }
}

/// One of the four quick action buttons: an icon over a word.
private struct QuickButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    init(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .frame(height: 18)
                Text(title)
            }
        }
        .buttonStyle(QuickButtonStyle())
    }
}

private struct QuickButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.sunken, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }
}

/// "Switch to": the workspaces, and Back to the running block.
private struct SwitchList: View {
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        HStack {
            Text("Switch to")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button("Back") {
                navigation.isSwitching = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.sunken, in: .rect(cornerRadius: 8))
        }
        .frame(minHeight: 36)

        VStack(spacing: 8) {
            ForEach(countdown.workspaces) { workspace in
                Button {
                    navigation.isSwitching = false
                    countdown.switchTo(workspace)
                } label: {
                    HStack(spacing: 12) {
                        WorkspaceDot(color: workspace.color)
                        Text(workspace.name)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(blockLength(workspace.defaultBlockMinutes))
                            .foregroundStyle(Color.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.sunken, in: .rect(cornerRadius: 12))
                    .contentShape(.rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WorkspaceDot: View {
    let color: WorkspaceColor

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: 10, height: 10)
    }
}

private struct Footer: View {
    let tracked: String

    var body: some View {
        Text("Today: \(tracked) tracked")
            .foregroundStyle(Color.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Color.line.frame(height: 1)
            }
    }
}

private extension Countdown {
    /// A countdown over the sample data in `scenario`, frozen at the sample's time.
    static func preview(_ scenario: TimerScenario) -> Countdown {
        let now = Date(timeIntervalSince1970: 1_768_466_490)
        let container = ModelContainer.sample
        if let context = container?.mainContext {
            // A preview without the scenario still shows the panel, so failing is fine here.
            try? scenario.apply(to: context, now: now)
        }
        return Countdown(container: container, fixedTime: now)
    }
}

#Preview("Running") {
    CompactPanelView(countdown: .preview(.running), navigation: PanelNavigation())
}

#Preview("Paused") {
    CompactPanelView(countdown: .preview(.paused), navigation: PanelNavigation())
}

#Preview("On a break") {
    CompactPanelView(countdown: .preview(.onBreak), navigation: PanelNavigation())
}

#Preview("Nothing running") {
    CompactPanelView(countdown: .preview(.idle), navigation: PanelNavigation())
}
