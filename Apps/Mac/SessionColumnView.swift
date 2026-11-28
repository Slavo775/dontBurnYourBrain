import DontBurnCore
import SwiftData
import SwiftUI

/// The sessions on this Mac in three groups, with their filter chips, or why
/// there are none.
struct SessionColumnView: View {
    let sessions: SessionColumn
    let settings: SettingsNavigation

    static let width: CGFloat = 460
    private static let inset: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 0) {
                Text("Sessions")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                Spacer(minLength: 10)
                if !sessions.list.isEmpty {
                    // Closer together when there are many, and scrolled
                    // sideways when they still do not fit.
                    ViewThatFits(in: .horizontal) {
                        SessionChips(sessions: sessions)
                        SessionChips(sessions: sessions, inset: 6)
                        ScrollView(.horizontal) {
                            SessionChips(sessions: sessions)
                        }
                        .scrollIndicators(.never)
                        // The track ends round, also where it is cut off.
                        .clipShape(.rect(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 36)

            if sessions.list.isEmpty {
                NoSessionsNote(reason: sessions.noSessions, settings: settings)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sessions.list.sections) { section in
                            SessionGroupView(
                                section: section, isFirst: section == sessions.list.sections.first, sessions: sessions,
                            )
                        }
                    }
                    .frame(width: Self.width - 2 * Self.inset, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, Self.inset)
                }
                // To the panel's edge, so a scroll bar lies in the padding and
                // the rows keep their width.
                .padding(.trailing, -Self.inset)
            }
        }
        .padding([.horizontal, .top], Self.inset)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The filter chips: All, one per workspace with a session, and Other.
private struct SessionChips: View {
    let sessions: SessionColumn
    /// The space on either side of a chip's text.
    var inset: CGFloat = 9

    var body: some View {
        HStack(spacing: 0) {
            ForEach(sessions.list.chips) { chip in
                let isChosen = chip.filter == sessions.list.filter
                Button {
                    sessions.show(chip.filter)
                } label: {
                    label(chip)
                        .fontWeight(isChosen ? .semibold : .regular)
                        .foregroundStyle(isChosen ? Color.ink : Color.muted)
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, inset)
                        .padding(.vertical, 5)
                        .background(isChosen ? Color.surface : Color.clear, in: .rect(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6).strokeBorder(isChosen ? Color.line : Color.clear)
                        }
                        .contentShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .font(.system(size: 12))
        .padding(2)
        .background(Color.sunken, in: .rect(cornerRadius: 8))
    }

    private func label(_ chip: SessionList.Chip) -> Text {
        switch chip.filter {
        case .all: Text("All \(chip.count)")
        case .workspace: Text(verbatim: "\(name(chip.workspaceName ?? "")) \(chip.count)")
        case .other: Text("Other \(chip.count)")
        }
    }

    private func name(_ workspace: String) -> String {
        workspace.isEmpty ? String(localized: "Unnamed") : workspace
    }
}

/// One group's heading and rows.
private struct SessionGroupView: View {
    let section: SessionList.Section
    let isFirst: Bool
    let sessions: SessionColumn

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(section.group == .needsYou ? Color.warn : Color.muted)
            .padding(.top, isFirst ? 0 : 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
        ForEach(section.rows) { row in
            SessionRow(
                row: row, group: section.group, note: sessions.notes[row.id], isFocusing: sessions.focusing == row.id,
            ) { sessions.focus(row.id) }
                .overlay(alignment: .top) {
                    if row != section.rows.first {
                        Color.line.frame(height: 1)
                    }
                }
        }
    }

    private var title: LocalizedStringKey {
        switch section.group {
        case .needsYou: "Needs you"
        case .working: "Working"
        case .idle: "Idle"
        }
    }
}

/// One session: its tile with the state's dot, its project or folder, then
/// its profile and terminal, or what the last Focus came to, its Focus button
/// in Terminal and iTerm2, and for an idle one the time since its last event.
///
/// VoiceOver reads the row as one element, and Focus is its action.
private struct SessionRow: View {
    let row: SessionList.Row
    let group: SessionGroup
    /// What the last Focus came to, when the row says it.
    let note: FocusOutcome?
    let isFocusing: Bool
    let focus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SessionTile(color: row.color, group: group)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title.isEmpty ? String(localized: "Unknown folder") : row.title)
                    .fontWeight(.semibold)
                if let noteText {
                    // Two lines, so a note beside Focus and the idle time is never cut.
                    Text(noteText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.warn)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.canFocus {
                Button("Focus", action: focus)
                    .buttonStyle(PanelButtonStyle(isProminent: true))
                    .fixedSize()
                    .disabled(isFocusing)
                    // The row's action, below, so the row stays one element.
                    .accessibilityHidden(true)
            }
            if let idleTime = row.idleTime {
                Text(text(idleTime))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
                    .fixedSize()
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            // The column ignores a second Focus while one runs.
            if row.canFocus {
                Button("Focus", action: focus)
            }
        }
    }

    /// What the last Focus came to, for the line under the name, or `nil` to
    /// show the profile and terminal.
    private var noteText: LocalizedStringKey? {
        let terminal = row.terminal?.name ?? ""
        switch note {
        case .gone: return "This session's tab is gone."
        case .timedOut: return "\(terminal) didn't answer. A dialog may be open."
        case .failed: return "\(terminal) could not be brought forward."
        case .focused, .denied, .notSent, nil: return nil
        }
    }

    /// The agent with its profile and terminal, without what is not known.
    private var source: LocalizedStringKey {
        switch (row.profile, row.terminal?.name) {
        case let (profile?, terminal?): "Claude (\(profile)) in \(terminal)"
        case let (profile?, nil): "Claude (\(profile))"
        case let (nil, terminal?): "Claude in \(terminal)"
        case (nil, nil): "Claude"
        }
    }

    private func text(_ idleTime: SessionList.IdleTime) -> LocalizedStringKey {
        switch idleTime {
        case .lessThanAMinute: "less than 1 min"
        case let .minutes(count): "\(count) min"
        case let .hours(count): "\(count) h"
        case let .days(count): "\(count) d"
        }
    }
}

/// The terminal on the workspace's color, or on the prototype's neutral tile
/// for a session in no project, with the state's dot at its corner.
/// VoiceOver skips it, because the group's heading says the state.
private struct SessionTile: View {
    /// The workspace's color, or `nil` for a session in no project.
    let color: WorkspaceColor?
    let group: SessionGroup

    var body: some View {
        Image(systemName: "terminal")
            .font(.system(size: 14))
            .foregroundStyle(color == nil ? Color.ink : Color.surface)
            .frame(width: 30, height: 30)
            .background(color?.color ?? Color.sunken, in: .rect(cornerRadius: 8))
            .opacity(group == .idle ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(dot)
                    .strokeBorder(Color.surface, lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .offset(x: 4, y: -4)
            }
            .accessibilityHidden(true)
    }

    private var dot: Color {
        switch group {
        case .needsYou: .warn
        case .working: .good
        case .idle: .muted
        }
    }
}

/// Why the column is empty. Without the hook, a link to where it is installed.
private struct NoSessionsNote: View {
    let reason: NoSessions
    let settings: SettingsNavigation

    var body: some View {
        switch reason {
        case .noneRunning:
            Text("No sessions on this Mac.")
                .foregroundStyle(Color.muted)
        case .hookNotInstalled:
            VStack(alignment: .leading, spacing: 12) {
                Text("The hook is not installed, so no session shows here.")
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
                OpenSettingsButton(sessionsTab: settings)
                    .buttonStyle(PanelButtonStyle())
            }
        }
    }
}

extension SessionColumn {
    /// The sample sessions of `scenario`, at the sample's time, for previews.
    static func preview(_ scenario: SessionScenario) -> SessionColumn {
        let now = Date(timeIntervalSince1970: 1_768_466_490)
        let container = ModelContainer.sample
        let localContainer = ModelContainer.sampleFolders(for: container)
        var monitor: SessionMonitor?
        if let container, let localContainer, let root = Bundle.main.sampleRoot {
            // A preview without its sessions still shows the column, so failing is fine here.
            try? SampleData.seedFolders(
                scenario.folders, into: localContainer.mainContext, projects: container.mainContext, root: root,
            )
            monitor = (try? scenario.store(root: root, now: now)).map(SessionMonitor.init(sample:))
        }
        let column = SessionColumn(
            monitor: monitor, focus: TerminalFocus(isSample: true), container: container,
            localContainer: localContainer, fixedTime: now,
        ) { scenario.hooks }
        column.isShown = true
        return column
    }
}

#Preview("Sessions") {
    SessionColumnView(sessions: .preview(.list), settings: SettingsNavigation())
        .panelSurface()
        .frame(width: 460, height: 460)
}

#Preview("No sessions") {
    SessionColumnView(sessions: .preview(.empty), settings: SettingsNavigation())
        .panelSurface()
        .frame(width: 460, height: 460)
}

#Preview("No hook") {
    SessionColumnView(sessions: .preview(.noHook), settings: SettingsNavigation())
        .panelSurface()
        .frame(width: 460, height: 460)
}
