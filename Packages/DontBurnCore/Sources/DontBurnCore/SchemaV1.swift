import Foundation
import SwiftData

// The rules iCloud sync needs from the first version: every attribute has a
// default or is optional, every relationship is optional with an inverse, and
// nothing is unique. Property names are permanent once sync goes live.

/// The first version of the data model.
public enum SchemaV1: VersionedSchema {
    /// The version number of this schema.
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    /// Every model of this version.
    public static var models: [any PersistentModel.Type] {
        [Workspace.self, Project.self, TimeBlock.self, TimeEntry.self]
    }

    /// The instant a date gets before it is set, so no default reads the clock.
    static let unsetDate = Date(timeIntervalSinceReferenceDate: 0)

    /// A separate area of work, such as one client, with its own settings.
    @Model
    public final class Workspace {
        /// The workspace's own identifier, kept across devices.
        public var id = UUID()
        /// The name shown in the interface.
        public var name = ""
        /// The key into the palette of six, `a` to `f`. See ``color``.
        public var colorKey = WorkspaceColor.teal.rawValue
        /// The position among the workspaces, lowest first.
        public var sortOrder = 0
        /// Whether the workspace is hidden from everyday use.
        public var isArchived = false
        /// The length a new block gets, in minutes.
        public var defaultBlockMinutes = 60
        /// The step the review screen rounds to, in minutes. Stored time is never rounded.
        public var roundingStepMinutes = 15
        /// Whether a break inside a block counts toward the hours sent on.
        public var breaksCount = true

        /// The workspace's projects. Deleting the workspace deletes them.
        @Relationship(deleteRule: .cascade, inverse: \Project.workspace)
        public var projects: [Project]?
        /// The workspace's blocks. Deleting the workspace deletes them.
        @Relationship(deleteRule: .cascade, inverse: \TimeBlock.workspace)
        public var blocks: [TimeBlock]?
        /// The workspace's entries. Deleting the workspace deletes them.
        @Relationship(deleteRule: .cascade, inverse: \TimeEntry.workspace)
        public var entries: [TimeEntry]?

        /// The palette color, or the first one when the stored key is unknown.
        public var color: WorkspaceColor {
            get { WorkspaceColor(rawValue: colorKey) ?? .teal }
            set { colorKey = newValue.rawValue }
        }

        /// A workspace with a name and a palette color.
        public init(name: String, color: WorkspaceColor, sortOrder: Int = 0) {
            self.name = name
            colorKey = color.rawValue
            self.sortOrder = sortOrder
        }
    }

    /// A piece of work inside one workspace that blocks and entries can name.
    @Model
    public final class Project {
        /// The project's own identifier, kept across devices.
        public var id = UUID()
        /// The name shown in the interface.
        public var name = ""
        /// The position among the workspace's projects, lowest first.
        public var sortOrder = 0
        /// Whether the project is hidden from everyday use.
        public var isArchived = false
        /// Whether time is tracked for this project. Blocks and entries may
        /// name only a tracked project.
        public var isTimeTracked = true

        /// The workspace the project belongs to.
        public var workspace: Workspace?
        /// The blocks naming this project. Deleting the project keeps them.
        ///
        /// Read-only outside the package, because setting this side would name
        /// the project without ``TimeBlock/assign(_:)``.
        @Relationship(deleteRule: .nullify, inverse: \TimeBlock.project)
        public internal(set) var blocks: [TimeBlock]?
        /// The entries naming this project. Deleting the project keeps them.
        ///
        /// Read-only outside the package, because setting this side would name
        /// the project without ``TimeEntry/assign(_:)``.
        @Relationship(deleteRule: .nullify, inverse: \TimeEntry.project)
        public internal(set) var entries: [TimeEntry]?

        /// A project inside `workspace`.
        public init(name: String, workspace: Workspace?, isTimeTracked: Bool = true, sortOrder: Int = 0) {
            self.name = name
            self.workspace = workspace
            self.isTimeTracked = isTimeTracked
            self.sortOrder = sortOrder
        }
    }

    /// Planned time for one workspace.
    @Model
    public final class TimeBlock {
        /// The block's own identifier, kept across devices.
        public var id = UUID()
        /// When the block is planned to start, as an absolute instant.
        public var plannedStart = SchemaV1.unsetDate
        /// How long the block is planned to last, in minutes.
        public var plannedMinutes = 0
        /// The stored form of ``state``.
        public var stateRaw = TimeBlockState.planned.rawValue

        /// The workspace the block belongs to.
        public var workspace: Workspace?
        /// The project the block is for. Set it with ``assign(_:)``.
        public internal(set) var project: Project?
        /// The entries tracked during the block. Deleting the block keeps them.
        @Relationship(deleteRule: .nullify, inverse: \TimeEntry.block)
        public var entries: [TimeEntry]?

        /// The block's state, or planned when the stored value is unknown.
        public var state: TimeBlockState {
            get { TimeBlockState(rawValue: stateRaw) ?? .planned }
            set { stateRaw = newValue.rawValue }
        }

        /// A planned block in `workspace`.
        public init(workspace: Workspace?, plannedStart: Date, plannedMinutes: Int, state: TimeBlockState = .planned) {
            self.workspace = workspace
            self.plannedStart = plannedStart
            self.plannedMinutes = plannedMinutes
            stateRaw = state.rawValue
        }
    }

    /// One real interval of tracked time.
    @Model
    public final class TimeEntry {
        /// The entry's own identifier, kept across devices.
        public var id = UUID()
        /// When the entry started, as an absolute instant.
        public var start = SchemaV1.unsetDate
        /// When the entry ended, or `nil` while it runs.
        public var end: Date?
        /// The stored form of ``kind``.
        public var kindRaw = TimeEntryKind.work.rawValue
        /// The stored form of ``source``.
        public var sourceRaw = TimeEntrySource.timer.rawValue
        /// A free note.
        public var note = ""
        /// How long the entry is planned to last, in minutes, or `nil` when it
        /// has no planned length.
        ///
        /// Set on break entries, so a break ends at the right moment even after
        /// the app was restarted.
        public var plannedMinutes: Int?

        /// The workspace the entry belongs to.
        public var workspace: Workspace?
        /// The project the entry is for. Set it with ``assign(_:)``.
        public internal(set) var project: Project?
        /// The block the entry was tracked in.
        public var block: TimeBlock?

        /// The entry's kind, or work when the stored value is unknown.
        public var kind: TimeEntryKind {
            get { TimeEntryKind(rawValue: kindRaw) ?? .work }
            set { kindRaw = newValue.rawValue }
        }

        /// Where the entry came from, or the timer when the stored value is unknown.
        public var source: TimeEntrySource {
            get { TimeEntrySource(rawValue: sourceRaw) ?? .timer }
            set { sourceRaw = newValue.rawValue }
        }

        /// An entry in `workspace` from `start` to `end`, or still running when `end` is `nil`.
        public init(
            workspace: Workspace?,
            start: Date,
            end: Date?,
            kind: TimeEntryKind = .work,
            source: TimeEntrySource = .timer,
            block: TimeBlock? = nil,
            note: String = "",
        ) {
            self.workspace = workspace
            self.start = start
            self.end = end
            kindRaw = kind.rawValue
            sourceRaw = source.rawValue
            self.block = block
            self.note = note
        }
    }
}

/// The palette of six workspace colors. The raw value is the stored key.
public enum WorkspaceColor: String, CaseIterable, Sendable {
    /// Key `a`.
    case teal = "a"
    /// Key `b`.
    case orange = "b"
    /// Key `c`.
    case indigo = "c"
    /// Key `d`.
    case raspberry = "d"
    /// Key `e`.
    case ochre = "e"
    /// Key `f`.
    case slate = "f"
}

/// Where a block is in its life.
public enum TimeBlockState: String, CaseIterable, Sendable {
    /// Not started yet.
    case planned
    /// Its time is being tracked now.
    case running
    /// Finished.
    case done
    /// Dropped without being finished.
    case cancelled
}

/// What a time entry was spent on.
public enum TimeEntryKind: String, CaseIterable, Sendable {
    /// Work on a task.
    case work
    /// A break.
    case `break`
    /// A meeting.
    case meeting
}

/// How a time entry came about.
public enum TimeEntrySource: String, CaseIterable, Sendable {
    /// Tracked by the timer.
    case timer
    /// Typed in by hand.
    case manual
    /// Taken from a calendar event.
    case calendar
}
