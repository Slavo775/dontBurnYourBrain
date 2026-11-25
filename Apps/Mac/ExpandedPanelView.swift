import DontBurnCore
import SwiftUI

/// The panel: compact, or wide with the sessions beside the block.
struct PanelView: View {
    let countdown: Countdown
    let sessions: SessionColumn
    let navigation: PanelNavigation
    let settings: SettingsNavigation
    let openWindow: () -> Void

    var body: some View {
        if navigation.isExpanded {
            ExpandedPanelView(
                countdown: countdown, sessions: sessions, navigation: navigation, settings: settings,
                openWindow: openWindow,
            )
        } else {
            CompactPanelView(countdown: countdown, navigation: navigation)
        }
    }
}

/// The wide panel: the timer on the left, the sessions on the right, and
/// today's totals below them.
struct ExpandedPanelView: View {
    let countdown: Countdown
    let sessions: SessionColumn
    let navigation: PanelNavigation
    let settings: SettingsNavigation
    let openWindow: () -> Void

    private static let width: CGFloat = 780
    private static let timerWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                TimerPart(countdown: countdown, navigation: navigation)
            }
            // Each column is read as a whole, not line by line across both.
            .accessibilityElement(children: .contain)
            .padding(22)
            .frame(width: Self.timerWidth, alignment: .leading)
            // The timer alone sets the height, so the panel never jumps as
            // sessions come and go. A longer list scrolls.
            .frame(minHeight: 500, alignment: .top)
            .frame(width: Self.width, alignment: .leading)
            .overlay(alignment: .trailing) {
                SessionColumnView(sessions: sessions, settings: settings)
                    .accessibilityElement(children: .contain)
                    .frame(width: Self.width - Self.timerWidth)
                    .overlay(alignment: .leading) {
                        Color.line.frame(width: 1)
                    }
            }
            ExpandedFooter(totals: countdown.totals, openWindow: openWindow)
        }
        .panelSurface()
    }
}

/// Today's totals per workspace, and the way to the window.
private struct ExpandedFooter: View {
    let totals: [DayLog.Total]
    let openWindow: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            // More workspaces than fit scroll sideways.
            ScrollView(.horizontal) {
                HStack(spacing: 22) {
                    ForEach(totals) { total in
                        HStack(spacing: 6) {
                            WorkspaceName(workspace: total.workspace)
                            Text(MenuBarLabel.hoursAndMinutes(total.tracked))
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .scrollIndicators(.never)
            Button(action: openWindow) {
                Text("Open window ⌘O")
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.surface, in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line)
                    }
                    .contentShape(.rect(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the window")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.sunken, in: .rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .overlay(alignment: .top) {
            Color.line.frame(height: 1)
        }
    }
}

@MainActor
private func expandedPanel(_ scenario: TimerScenario, _ sessions: SessionScenario) -> some View {
    let navigation = PanelNavigation()
    navigation.isExpanded = true
    let countdown = Countdown.preview(scenario)
    countdown.isPanelOpen = true
    return PanelView(
        countdown: countdown, sessions: .preview(sessions), navigation: navigation, settings: SettingsNavigation(),
    ) {}
}

#Preview("Running") {
    expandedPanel(.running, .list)
}

#Preview("Nothing running") {
    expandedPanel(.idle, .list)
}

#Preview("Many sessions") {
    expandedPanel(.paused, .many)
}

#Preview("No sessions") {
    expandedPanel(.running, .empty)
}

#Preview("No hook") {
    expandedPanel(.idle, .noHook)
}
