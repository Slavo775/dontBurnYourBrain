import Foundation
import SwiftData

// Version 1 plus the focus presets: a workspace names its default preset, and a
// block keeps its own copy of the rhythm it started with. The sync rules of
// version 1 hold here too, and every name here is permanent once sync goes live.

/// The second version of the data model.
public enum SchemaV2: VersionedSchema {
    /// The version number of this schema.
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    /// Every model of this version.
    public static var models: [any PersistentModel.Type] {
        [Workspace.self, Project.self, TimeBlock.self, TimeEntry.self, FocusPreset.self]
    }

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
        /// The rhythm a new block follows, or `nil` for none, so its blocks
        /// run as they did before presets.
        public var focusPreset: FocusPreset?

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
    ///
    /// A block with a rhythm keeps its own copy of it, made when it starts, so
    /// a later change to the preset never rewrites it. The copy is read-only
    /// outside the package for the same reason. A block whose focus or break
    /// minutes are zero has no rhythm, as every block from version 1.
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
        /// The minutes of each focus interval, or 0 when the block has no rhythm.
        public internal(set) var focusMinutes = 0
        /// The minutes of a short planned break, or 0 when the block has no rhythm.
        public internal(set) var breakMinutes = 0
        /// The minutes of a long planned break, or 0 for none.
        public internal(set) var longBreakMinutes = 0
        /// Every how many breaks the long one comes, or 0 for none.
        public internal(set) var roundsBeforeLongBreak = 0
        /// Whether work goes on by itself when a break ends, or the block
        /// waits paused for Resume. Read only when the block has a rhythm.
        public internal(set) var resumesAfterBreak = true

        /// The workspace the block belongs to.
        public var workspace: Workspace?
        /// The project the block is for. Set it with ``assign(_:)``.
        public internal(set) var project: Project?
        /// The entries tracked during the block. Deleting the block keeps them.
        @Relationship(deleteRule: .nullify, inverse: \TimeEntry.block)
        public var entries: [TimeEntry]?
        /// The preset the block's rhythm was copied from, or `nil` when it had
        /// none or the preset was deleted since.
        public internal(set) var focusPreset: FocusPreset?

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

    /// A rhythm of focus intervals and breaks that a block can follow.
    ///
    /// Deleting a preset clears it from its workspaces and blocks. A block
    /// keeps its own copy of the rhythm, so it runs on unchanged.
    @Model
    public final class FocusPreset {
        /// The preset's own identifier, kept across devices. The presets the
        /// app comes with have fixed ones. See ``seedDefaults(into:)``.
        public var id = UUID()
        /// The name shown in the interface.
        public var name = ""
        /// The minutes of each focus interval.
        public var focusMinutes = 25
        /// The minutes of a short break.
        public var breakMinutes = 5
        /// The minutes of a long break, or 0 for none.
        public var longBreakMinutes = 0
        /// Every how many breaks the long one comes, or 0 for none.
        public var roundsBeforeLongBreak = 0
        /// Whether work goes on by itself when a break ends, or the block waits paused for Resume.
        public var resumesAfterBreak = true

        /// The workspaces whose new blocks follow this preset.
        @Relationship(deleteRule: .nullify, inverse: \Workspace.focusPreset)
        public var workspaces: [Workspace]?
        /// The blocks whose rhythm was copied from this preset.
        @Relationship(deleteRule: .nullify, inverse: \TimeBlock.focusPreset)
        public var blocks: [TimeBlock]?

        /// A preset of `focusMinutes` of focus and `breakMinutes` of break,
        /// with a long break of `longBreakMinutes` every `roundsBeforeLongBreak`
        /// breaks when both are above zero.
        public init(
            name: String,
            focusMinutes: Int,
            breakMinutes: Int,
            longBreakMinutes: Int = 0,
            roundsBeforeLongBreak: Int = 0,
            resumesAfterBreak: Bool = true,
        ) {
            self.name = name
            self.focusMinutes = focusMinutes
            self.breakMinutes = breakMinutes
            self.longBreakMinutes = longBreakMinutes
            self.roundsBeforeLongBreak = roundsBeforeLongBreak
            self.resumesAfterBreak = resumesAfterBreak
        }
    }
}

/// A separate area of work. See ``SchemaV2/Workspace``.
public typealias Workspace = SchemaV2.Workspace
/// A piece of work inside a workspace. See ``SchemaV2/Project``.
public typealias Project = SchemaV2.Project
/// Planned time for one workspace. See ``SchemaV2/TimeBlock``.
public typealias TimeBlock = SchemaV2.TimeBlock
/// One real interval of tracked time. See ``SchemaV2/TimeEntry``.
public typealias TimeEntry = SchemaV2.TimeEntry
/// A rhythm of focus intervals and breaks. See ``SchemaV2/FocusPreset``.
public typealias FocusPreset = SchemaV2.FocusPreset
