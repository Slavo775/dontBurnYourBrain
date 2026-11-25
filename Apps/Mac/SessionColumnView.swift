import DontBurnCore
import SwiftData
import SwiftUI

/// The sessions on this Mac in three groups, with their filter chips, or why
/// there are none.
struct SessionColumnView: View {
    let sessions: SessionColumn
    let settings: SettingsNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Text("Sessions")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                Spacer(minLength: 0)
                if !sessions.list.isEmpty {
                    // More chips than fit scroll sideways.
                    ViewThatFits(in: .horizontal) {
                        SessionChips(sessions: sessions)
                        ScrollView(.horizontal) {
                            SessionChips(sessions: sessions)
                        }
                        .scrollIndicators(.never)
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
                            SessionGroupView(section: section, isFirst: section == sessions.list.sections.first)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding([.horizontal, .top], 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The filter chips: All, one per workspace with a session, and Other.
private struct SessionChips: View {
    let sessions: SessionColumn

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
                        .padding(.horizontal, 9)
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

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(section.group == .needsYou ? Color.warn : Color.muted)
            .padding(.top, isFirst ? 0 : 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
        ForEach(section.rows) { row in
            SessionRow(row: row, group: section.group)
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
/// its profile and terminal, and for an idle one the time since its last event.
private struct SessionRow: View {
    let row: SessionList.Row
    let group: SessionGroup

    var body: some View {
        HStack(spacing: 12) {
            SessionTile(color: row.color, group: group)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title.isEmpty ? String(localized: "Unknown folder") : row.title)
                    .fontWeight(.semibold)
                Group {
                    if let terminal = row.terminal {
                        Text("Claude (\(row.profile)) in \(terminal.name)")
                    } else {
                        Text("Claude (\(row.profile))")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let minutes = row.idleMinutes {
                Text(idleTime(minutes))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Color.muted)
                    .fixedSize()
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    /// In the largest unit that fits, such as `12 min`, `3 h` or `2 d`.
    private func idleTime(_ minutes: Int) -> LocalizedStringKey {
        switch minutes {
        case 0: "less than 1 min"
        case ..<60: "\(minutes) min"
        case ..<(24 * 60): "\(minutes / 60) h"
        default: "\(minutes / (24 * 60)) d"
        }
    }
}

/// The terminal on the workspace's color, with the state's dot at its corner.
/// VoiceOver skips it, because the group's heading says the state.
private struct SessionTile: View {
    /// The workspace's color, or `nil` for a session in no project.
    let color: WorkspaceColor?
    let group: SessionGroup

    var body: some View {
        Image(systemName: "terminal")
            .font(.system(size: 14))
            .foregroundStyle(Color.surface)
            .frame(width: 30, height: 30)
            .background(color?.color ?? Color.muted, in: .rect(cornerRadius: 8))
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
            monitor: monitor, container: container, localContainer: localContainer, fixedTime: now,
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
