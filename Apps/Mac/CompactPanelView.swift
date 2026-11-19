import DontBurnCore
import SwiftData
import SwiftUI

/// The compact panel: the running block or break, its four quick actions and
/// End block, the list of workspaces to switch to, the break's lengths, or,
/// when nothing runs, the quick start list and the custom block form.
struct CompactPanelView: View {
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if navigation.page == .breakLength {
                BreakLengthList(countdown: countdown, navigation: navigation)
            } else if let panel = countdown.panel {
                if navigation.page == .switching {
                    WorkspaceList(title: "Switch to", countdown: countdown, navigation: navigation)
                } else {
                    RunningBlock(panel: panel, countdown: countdown, navigation: navigation)
                }
            } else if navigation.page == .customBlock {
                CustomBlockForm(countdown: countdown, navigation: navigation)
            } else if countdown.hasStore, countdown.workspaces.isEmpty {
                NoWorkspaces(navigation: navigation)
            } else {
                WorkspaceList(title: "Nothing running", countdown: countdown, navigation: navigation)
            }
            if countdown.panel != nil, countdown.alerts?.isAskingPermission == true {
                // Below the actions, so they keep their places.
                Text("Allow notifications to hear when a block or break ends")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tracked = countdown.panel?.trackedToday ?? countdown.trackedToday {
                Footer(tracked: tracked)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ink)
        .padding(20)
        .frame(width: 328, alignment: .leading)
        .background(Color.surface, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ring)
        }
    }
}

/// The header, the countdown, the strip, the four quick actions and End
/// block. A break with no block has the cup for a header and no End block.
private struct RunningBlock: View {
    let panel: CompactPanel
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        HStack(spacing: 10) {
            if panel.state == .idleBreak {
                Image(systemName: "cup.and.heat.waves")
                    .accessibilityHidden(true)
                Text("Break")
                    .font(.system(size: 15, weight: .semibold))
            } else {
                WorkspaceDot(color: panel.color)
                Text(panel.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
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
                (panel.state.isBreak ? Color.muted : panel.color.color)
                    .scaleEffect(x: panel.progress, anchor: .leading)
            }
            .frame(height: 8)
            .clipShape(.rect(cornerRadius: 4))
            .padding(.top, 6)
            .accessibilityHidden(true)
        }

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                QuickButton(
                    panel.state == .paused ? "Resume" : "Pause",
                    symbol: panel.state == .paused ? "play.fill" : "pause.fill",
                ) {
                    countdown.perform(.pauseOrResume)
                }
                .disabled(!QuickAction.pauseOrResume.isAvailable(in: panel.state))
                QuickButton(panel.state.isBreak ? "End break" : "Break", symbol: "cup.and.heat.waves") {
                    if QuickAction.canStartBreak(in: panel.state) {
                        navigation.page = .breakLength
                    } else {
                        countdown.perform(.breakOrEndBreak)
                    }
                }
                .disabled(!QuickAction.breakOrEndBreak.isAvailable(in: panel.state))
                Button {
                    countdown.perform(.extend)
                } label: {
                    VStack(spacing: 6) {
                        Text(verbatim: "+15")
                            .font(.system(size: 16, weight: .semibold))
                            .monospacedDigit()
                            .frame(height: 18)
                        Text("min")
                    }
                }
                .buttonStyle(QuickButtonStyle())
                .accessibilityLabel("Add 15 minutes")
                QuickButton("Switch", symbol: "arrow.left.arrow.right") {
                    navigation.page = .switching
                }
                // With no workspace there is nothing to switch to.
                .disabled(countdown.workspaces.isEmpty)
            }

            // Under the four actions, so they keep their places. Outlined like
            // "Custom block", so it reads quieter than the four.
            if panel.state.hasBlock {
                Button {
                    countdown.endBlock()
                } label: {
                    StartRow(key: "E", isGhost: true) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.muted)
                            .frame(width: 10)
                        Text("End block")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End block")
            }
        }
    }

    private var line: LocalizedStringKey {
        switch panel.line {
        case let .leftOf(length): "left of \(length)"
        case .paused: "Paused"
        case let .onBreak(name): "On a break, then back to \(name)"
        case .idleBreak: "On a break, nothing running"
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
            .background(configuration.isPressed ? Color.line : Color.sunken, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A panel title on the left, and an optional control on the right.
struct PanelTitle<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            trailing
        }
        .frame(minHeight: 36)
    }
}

struct PanelBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Back")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.sunken, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct WorkspaceDot: View {
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
        return Countdown(container: container, fixedTime: now, idleBreak: scenario.idleBreak(at: now))
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

#Preview("Break with nothing running") {
    CompactPanelView(countdown: .preview(.idleBreak), navigation: PanelNavigation())
}

#Preview("Break for") {
    let navigation = PanelNavigation()
    navigation.page = .breakLength
    return CompactPanelView(countdown: .preview(.running), navigation: navigation)
}

#Preview("Nothing running") {
    CompactPanelView(countdown: .preview(.idle), navigation: PanelNavigation())
}

#Preview("Custom block") {
    let countdown = Countdown.preview(.idle)
    let navigation = PanelNavigation()
    navigation.openCustomBlock(countdown.workspaces)
    return CompactPanelView(countdown: countdown, navigation: navigation)
}

#Preview("Switch to") {
    let navigation = PanelNavigation()
    navigation.page = .switching
    return CompactPanelView(countdown: .preview(.running), navigation: navigation)
}

#Preview("No workspaces") {
    // An empty store in memory: the panel leads to Settings.
    CompactPanelView(
        countdown: Countdown(container: try? ModelStore.inMemory(), fixedTime: .now),
        navigation: PanelNavigation(),
    )
}

#Preview("No store") {
    CompactPanelView(countdown: Countdown(container: nil, fixedTime: .now), navigation: PanelNavigation())
}
