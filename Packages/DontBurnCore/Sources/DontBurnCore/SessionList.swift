import Foundation

/// Which sessions the session list shows.
public enum SessionFilter: Hashable, Sendable {
    /// Every session.
    case all
    /// The sessions in the projects of the workspace with this ``SchemaV2/Workspace/id``.
    case workspace(UUID)
    /// The sessions in no project's folder.
    case other
}

/// A terminal app the session list can name, by its bundle identifier.
public enum TerminalApp: String, CaseIterable, Sendable {
    /// Apple's Terminal.
    case terminal = "com.apple.Terminal"
    /// iTerm2.
    case iTerm2 = "com.googlecode.iterm2"
    /// Visual Studio Code.
    case visualStudioCode = "com.microsoft.VSCode"
    /// Cursor.
    case cursor = "com.todesktop.230313mzl4w4u92"

    /// The app's name, a product name that is the same in every language.
    public var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iTerm2: "iTerm2"
        case .visualStudioCode: "VS Code"
        case .cursor: "Cursor"
        }
    }
}

/// The session list at one moment: its filter chips, and its rows in three groups.
///
/// It depends on nothing but the sessions, so it is the same with a block
/// running, paused and with nothing running, and a session of a project whose
/// time is not tracked is a row like any other.
public struct SessionList: Equatable, Sendable {
    /// One filter the list offers.
    public struct Chip: Equatable, Identifiable, Sendable {
        /// What the chip shows when it is chosen.
        public let filter: SessionFilter
        /// The workspace's name, or `nil` for All and Other, which the app names.
        public let workspaceName: String?
        /// How many sessions the chip shows.
        public let count: Int

        /// The chip's filter.
        public var id: SessionFilter {
            filter
        }
    }

    /// One session.
    public struct Row: Equatable, Identifiable, Sendable {
        /// The session's id.
        public let id: String
        /// The project's name, or the folder's name for a session in no
        /// project and for a project without a name. Empty when neither has one.
        public let title: String
        /// The color of the project's workspace, or `nil` for a session in no project.
        public let color: WorkspaceColor?
        /// The profile's short name: its folder's name without `.claude-` in
        /// front, or the whole name of another folder. `nil` for the default profile.
        public let profile: String?
        /// The terminal app, or `nil` when it is unknown.
        public let terminal: TerminalApp?
        /// The whole minutes since the last activity, rounded down, for an
        /// idle session, and `nil` for any other.
        public let idleMinutes: Int?
        /// Whether the row has a Focus button, whatever its group: the session
        /// has a ``AgentSession/focusHandle``, and macOS has not refused the
        /// app control of its terminal.
        public let canFocus: Bool

        /// ``idleMinutes`` in the largest unit that fits.
        public var idleTime: IdleTime? {
            idleMinutes.map(IdleTime.init(minutes:))
        }
    }

    /// How long a session has been idle, in one unit, rounded down.
    public enum IdleTime: Equatable, Sendable {
        /// Less than one minute.
        case lessThanAMinute
        /// 1 to 59 minutes.
        case minutes(Int)
        /// 1 to 23 hours.
        case hours(Int)
        /// One day or more.
        case days(Int)

        /// The whole `minutes` in the largest unit that fits.
        public init(minutes: Int) {
            switch minutes {
            case ..<1: self = .lessThanAMinute
            case ..<60: self = .minutes(minutes)
            case ..<(24 * 60): self = .hours(minutes / 60)
            default: self = .days(minutes / (24 * 60))
            }
        }
    }

    /// The rows of one group.
    public struct Section: Equatable, Identifiable, Sendable {
        /// The group.
        public let group: SessionGroup
        /// Its rows, never empty.
        public let rows: [Row]

        /// The section's group.
        public var id: SessionGroup {
            group
        }
    }

    /// The filter in use: the one asked for, or ``SessionFilter/all`` when no
    /// session is left for it.
    public let filter: SessionFilter
    /// All, then the workspaces with a session in their order, then Other when
    /// a session is in no project. Empty when there is no session at all.
    public let chips: [Chip]
    /// The groups with a row under ``filter``, in the order of ``SessionGroup``.
    ///
    /// Needs you and Working keep the order of the sessions, oldest first, so
    /// no row moves as its events come in. Idle starts with the one that was
    /// active last.
    public let sections: [Section]

    /// Whether there is no session, under any filter.
    public var isEmpty: Bool {
        chips.isEmpty
    }

    /// The list of `sessions` at `now` under `filter`.
    ///
    /// `project` finds a session's project, as
    /// ``AgentSession/project(in:among:)`` does. A project without a workspace
    /// counts as none. A session that ended is left out. The sessions in a
    /// terminal of `automationDenied` get no Focus button.
    public init(
        sessions: [AgentSession],
        filter: SessionFilter = .all,
        automationDenied: Set<TerminalApp> = [],
        at now: Date,
        project: (AgentSession) throws -> Project?,
    ) rethrows {
        let listed = try sessions.compactMap { session in
            try session.state(at: now).group.map { group in
                try Listed(session: session, group: group, project: project(session))
            }
        }
        chips = Self.chips(for: listed)
        let filter = chips.contains { $0.filter == filter } ? filter : .all
        self.filter = filter
        let shown = filter == .all ? listed : listed.filter { $0.filter == filter }
        sections = SessionGroup.allCases.compactMap { group in
            let rows = Self.ordered(shown.filter { $0.group == group }, in: group).map {
                $0.row(at: now, automationDenied: automationDenied)
            }
            return rows.isEmpty ? nil : Section(group: group, rows: rows)
        }
    }

    private static func chips(for listed: [Listed]) -> [Chip] {
        guard !listed.isEmpty else { return [] }
        var workspaces: [UUID: Workspace] = [:]
        var counts: [SessionFilter: Int] = [:]
        for item in listed {
            counts[item.filter, default: 0] += 1
            if let workspace = item.project?.workspace {
                workspaces[workspace.id] = workspace
            }
        }
        let named = workspaces.values
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
            .map { workspace in
                let filter = SessionFilter.workspace(workspace.id)
                return Chip(filter: filter, workspaceName: workspace.name, count: counts[filter] ?? 0)
            }
        let all = Chip(filter: .all, workspaceName: nil, count: listed.count)
        let other = counts[.other].map { Chip(filter: .other, workspaceName: nil, count: $0) }
        return [all] + named + [other].compactMap(\.self)
    }

    private static func ordered(_ listed: [Listed], in group: SessionGroup) -> [Listed] {
        switch group {
        case .needsYou, .working: listed
        case .idle: listed.sorted { $0.session.lastActivity > $1.session.lastActivity }
        }
    }

    /// A session with its group and its project.
    private struct Listed {
        let session: AgentSession
        let group: SessionGroup
        /// The project, only when it has a workspace.
        let project: Project?

        init(session: AgentSession, group: SessionGroup, project: Project?) {
            self.session = session
            self.group = group
            self.project = project?.workspace == nil ? nil : project
        }

        /// The filter that shows the session, besides All.
        var filter: SessionFilter {
            project?.workspace.map { .workspace($0.id) } ?? .other
        }

        func row(at now: Date, automationDenied: Set<TerminalApp>) -> Row {
            let name = project?.name ?? ""
            // Through the capped rounding, so a damaged stored time never stops the app.
            let idle = MenuBarLabel.wholeSeconds(now.timeIntervalSince(session.lastActivity)) / 60
            return Row(
                id: session.id,
                title: name.isEmpty ? session.folderName : name,
                color: project?.workspace?.color,
                profile: Self.shortName(ofProfile: session.profileName),
                terminal: session.terminalBundleIdentifier.flatMap(TerminalApp.init(rawValue:)),
                idleMinutes: group == .idle ? idle : nil,
                canFocus: session.focusHandle.map { !automationDenied.contains($0.terminal) } ?? false,
            )
        }

        /// See ``Row/profile``. A folder without a name counts as the default profile.
        private static func shortName(ofProfile folder: String) -> String? {
            guard !folder.isEmpty, folder != AgentSession.defaultProfileName else { return nil }
            let prefix = AgentSession.defaultProfileName + "-"
            return folder.hasPrefix(prefix) && folder != prefix ? String(folder.dropFirst(prefix.count)) : folder
        }
    }
}

/// Why the session list is empty.
public enum NoSessions: Equatable, Sendable {
    /// The hook is installed, and no session runs.
    case noneRunning
    /// No profile has the hook, so no session can report to the app.
    case hookNotInstalled

    /// The reason while no session runs, from the hook of each profile:
    /// ``hookNotInstalled`` when none of `hooks` is an installed one.
    public init(hooks: some Sequence<HookStatus>) {
        let isInstalled = hooks.contains { $0 == .installed || $0 == .foundWithoutRecord }
        self = isInstalled ? .noneRunning : .hookNotInstalled
    }
}
