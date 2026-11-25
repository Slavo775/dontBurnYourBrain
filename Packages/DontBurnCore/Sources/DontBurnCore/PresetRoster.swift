import Foundation
import SwiftData

/// Why the preset roster refused an operation. Nothing was changed.
public enum PresetRosterError: Error, Equatable, Sendable {
    /// A workspace, archived or not, names the preset.
    case inUse
}

/// Lists, creates and removes the focus presets, and keeps their numbers in range.
///
/// A preset has no order of its own, so the list sorts them, see ``order``.
/// One that a workspace names stays. The data model cannot say so, because
/// sync allows no such delete rule, so it is checked here. A block keeps its
/// own copy of its rhythm, so removing a preset never touches a block. Every
/// operation saves the context.
public struct PresetRoster {
    /// The minutes a focus interval or a break may be given.
    public static let minuteRange = 1 ... 240
    /// The rounds a long break may be given.
    public static let roundRange = 2 ... 12
    /// The focus minutes of a new preset.
    public static let newFocusMinutes = 25
    /// The break minutes of a new preset.
    public static let newBreakMinutes = 5

    private let context: ModelContext

    /// A roster working on the presets in `context`.
    public init(context: ModelContext) {
        self.context = context
    }

    /// The order the presets are listed in: by focus minutes, then break minutes, then name.
    public static var order: [SortDescriptor<FocusPreset>] {
        [SortDescriptor(\.focusMinutes), SortDescriptor(\.breakMinutes), SortDescriptor(\.name)]
    }

    /// Every preset, in ``order``.
    public func presets() throws -> [FocusPreset] {
        try context.fetch(FetchDescriptor(sortBy: Self.order))
    }

    /// The rhythm of the preset with `id`, or none when `id` is `nil` or no preset has it.
    public func rhythm(ofPreset id: FocusPreset.ID?) throws -> BlockRhythm {
        try presets().first { $0.id == id }.map(BlockRhythm.preset) ?? BlockRhythm.none
    }

    /// Adds a preset of ``newFocusMinutes`` and ``newBreakMinutes`` and returns it.
    ///
    /// It is named `baseName`, or `baseName` with a number when a preset
    /// already has that name. It has no long break, and work resumes by itself.
    @discardableResult
    public func create(baseName: String) throws -> FocusPreset {
        let preset = try FocusPreset(
            name: WorkspaceRoster.uniqueName(base: baseName, taken: presets().map(\.name)),
            focusMinutes: Self.newFocusMinutes,
            breakMinutes: Self.newBreakMinutes,
        )
        context.insert(preset)
        try context.save()
        return preset
    }

    /// The workspaces among `workspaces` that name `preset`, in their order.
    ///
    /// While there is one, archived ones included, the preset cannot be removed.
    public static func workspaces(naming preset: FocusPreset, among workspaces: [Workspace]) -> [Workspace] {
        workspaces.filter { $0.focusPreset?.id == preset.id }
    }

    /// Deletes `preset`, or throws ``PresetRosterError/inUse`` while a workspace names it.
    public func remove(_ preset: FocusPreset) throws {
        let all = try context.fetch(FetchDescriptor<Workspace>())
        guard Self.workspaces(naming: preset, among: all).isEmpty else { throw PresetRosterError.inUse }
        context.delete(preset)
        try context.save()
    }

    /// `edited` moved into `range`, or unchanged while it equals `stored`, so
    /// a stored number outside the range stays until it is edited.
    public static func number(_ edited: Int, replacing stored: Int, in range: ClosedRange<Int>) -> Int {
        edited == stored ? stored : clamped(edited, to: range)
    }

    /// `stored` one step of `step` up or down, inside `range`, whatever is stored.
    public static func number(_ stored: Int, steppedBy step: Int, in range: ClosedRange<Int>) -> Int {
        clamped(clamped(stored, to: range) + step, to: range)
    }

    private static func clamped(_ number: Int, to range: ClosedRange<Int>) -> Int {
        min(max(number, range.lowerBound), range.upperBound)
    }
}

public extension FocusPreset {
    /// Whether every so many breaks is a long one.
    ///
    /// Switching it on starts at 15 minutes after 4 rounds, and switching it
    /// off stores 0 for both. Setting what it already is changes nothing.
    var hasLongBreak: Bool {
        get { longBreakMinutes > 0 && roundsBeforeLongBreak > 0 }
        set {
            guard newValue != hasLongBreak else { return }
            longBreakMinutes = newValue ? 15 : 0
            roundsBeforeLongBreak = newValue ? 4 : 0
        }
    }
}
