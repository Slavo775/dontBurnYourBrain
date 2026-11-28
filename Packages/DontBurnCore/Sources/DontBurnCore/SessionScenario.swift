import Foundation

/// A state of the session list the sample data can be put into, for screenshots.
///
/// The sessions are made from hook events laid out relative to the `now` they
/// are given, so with a fixed time the list looks the same on every launch.
public enum SessionScenario: String, CaseIterable, Sendable {
    /// Six sessions: one that needs you, two at work and three idle ones, in
    /// all three sample workspaces and in no project, one of them in Reading,
    /// whose time is not tracked.
    case list
    /// Those six, five times over, and one in a folder with a very long name.
    case many
    /// No session, and the hook is installed.
    case empty = "none"
    /// No session, and the hook is in no profile.
    case noHook = "no-hook"

    /// The scenario a launch argument's value names, such as `no-hook` in
    /// `-DontBurnSessionState no-hook`, or ``list`` without one.
    ///
    /// The value is input from outside the app. Anything but one of the raw
    /// values, exactly, is ``list`` too.
    public init(launchArgument raw: String?) {
        self = raw.flatMap { $0.utf8.count <= 16 ? Self(rawValue: $0) : nil } ?? .list
    }

    /// What the check of the profiles' hooks finds, so a run with the sample
    /// data reads no profile.
    public var hooks: [HookStatus] {
        self == .noHook ? [.notInstalled] : [.installed]
    }

    /// The folders beside ``SampleData/folders`` that this scenario's sessions
    /// need, by project name. Without sessions there are none, so Reading
    /// stays a project without a folder there.
    public var folders: [String: [String]] {
        samples.isEmpty ? [:] : ["Reading": ["code/reading-notes"]]
    }

    /// The scenario's sessions at `now`, with their folders and profiles below
    /// `root`, the sample root.
    ///
    /// Nothing is read or made on disk. Each session's process ID is above any
    /// that macOS gives out, so it never names a real process. A session in
    /// iTerm2 or Terminal has a made-up tab handle, so its row shows Focus, and
    /// the app sends no Apple event with the sample data.
    public func store(root: URL, now: Date) throws -> SessionStore {
        func path(_ folder: String) -> String {
            root.appending(path: folder).path(percentEncoded: false)
        }
        var store = SessionStore()
        for (index, sample) in samples.enumerated() {
            for (name, minutesAgo) in sample.events {
                let message = try JSONEncoder().encode([
                    "hook_event_name": name, "session_id": "sample-\(index)", "cwd": path(sample.folder),
                ])
                var environment = ["CLAUDE_PID": "\(Int32.max - Int32(index))"]
                environment["CLAUDE_CONFIG_DIR"] = sample.profile.map(path)
                environment["__CFBundleIdentifier"] = sample.terminal?.rawValue
                environment["ITERM_SESSION_ID"] = sample.terminal == .iTerm2
                    ? String(format: "w0t0p0:00000000-0000-4000-8000-%012d", index)
                    : nil
                let tty = sample.terminal == .terminal ? String(format: "ttys9%02d", index) : nil
                let event = try HookEvent(claudeEvent: message, environment: environment) { _ in tty }
                store.apply(event, at: now.addingTimeInterval(-minutesAgo * 60))
            }
        }
        return store
    }

    private var samples: [Sample] {
        switch self {
        case .list: Sample.list
        case .many: Array(repeating: Sample.list, count: 5).flatMap(\.self) + [Sample.longName]
        case .empty, .noHook: []
        }
    }

    /// One sample session.
    private struct Sample {
        /// The folder below the sample root.
        let folder: String
        /// The profile folder below the sample root, or `nil` for the default profile.
        let profile: String?
        let terminal: TerminalApp?
        /// The events, earliest first, each with how many minutes ago it came.
        let events: [(name: String, minutesAgo: Double)]

        /// Oldest first, as the store keeps them.
        static let list = [
            Sample(
                folder: "code/scratch", profile: nil, terminal: nil,
                events: [("SessionStart", 200), ("UserPromptSubmit", 190), ("Stop", 185)],
            ),
            Sample(
                folder: "code/acme-web", profile: ".claude-acme", terminal: .iTerm2,
                events: [("SessionStart", 95), ("UserPromptSubmit", 6), ("PermissionRequest", 2)],
            ),
            Sample(
                folder: "code/acme-mobile", profile: ".claude-acme", terminal: .cursor,
                events: [("SessionStart", 60), ("UserPromptSubmit", 1)],
            ),
            Sample(
                folder: "code/reading-notes", profile: ".claude-personal", terminal: .iTerm2,
                events: [("SessionStart", 50), ("UserPromptSubmit", 45), ("Stop", 40)],
            ),
            Sample(
                folder: "code/globex-data", profile: ".claude-globex", terminal: .visualStudioCode,
                events: [("SessionStart", 30), ("UserPromptSubmit", 4)],
            ),
            Sample(
                folder: "code/side-project", profile: ".claude-personal", terminal: .terminal,
                events: [("SessionStart", 12)],
            ),
        ]

        static let longName = Sample(
            folder: "code/a-scratch-folder-with-a-name-far-too-long-to-fit-into-one-row-of-the-session-list",
            profile: ".claude-a-profile-with-a-long-name-of-its-own", terminal: .visualStudioCode,
            events: [("SessionStart", 10), ("UserPromptSubmit", 3)],
        )
    }
}
