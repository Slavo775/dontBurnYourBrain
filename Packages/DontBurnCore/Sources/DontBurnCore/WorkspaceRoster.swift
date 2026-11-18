import Foundation
import SwiftData

/// Creates, orders, archives and restores workspaces.
///
/// A workspace is never deleted: its blocks and entries would go with it.
/// Removing one archives it instead. The active workspaces keep a dense
/// ``SchemaV1/Workspace/sortOrder`` from 0, which is also the order of quick
/// start and its number keys. Every operation saves the context.
public struct WorkspaceRoster {
    /// The default block length of a new workspace, in minutes.
    public static let defaultBlockMinutes = 60

    /// The block lengths offered for a workspace, in minutes, shortest first.
    public static let blockLengthChoices = [25, 30, 45, 60, 90, 120, 180, 240]

    /// How many workspaces get a quick start number key, 1 to 9.
    public static let quickStartKeyCount = 9

    private let context: ModelContext

    /// A roster working on the workspaces in `context`.
    public init(context: ModelContext) {
        self.context = context
    }

    /// The workspaces in everyday use, in their order.
    public func activeWorkspaces() throws -> [Workspace] {
        try context.fetch(FetchDescriptor<Workspace>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortOrder)],
        ))
    }

    /// Adds a workspace at the end of the active ones and returns it.
    ///
    /// It is named `baseName`, or `baseName` with a number when a workspace
    /// already has that name, gets the first color no active workspace uses
    /// and a block of ``defaultBlockMinutes``.
    @discardableResult
    public func create(baseName: String) throws -> Workspace {
        let active = try activeWorkspaces()
        let names = try context.fetch(FetchDescriptor<Workspace>()).map(\.name)
        let workspace = Workspace(
            name: Self.uniqueName(base: baseName, taken: names),
            color: Self.firstUnusedColor(used: active.map(\.color)),
        )
        workspace.defaultBlockMinutes = Self.defaultBlockMinutes
        context.insert(workspace)
        renumber(active + [workspace])
        try context.save()
        return workspace
    }

    /// Moves the active workspaces at `offsets` to before `destination`, as a
    /// list's drag and drop reports it.
    public func move(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        try renumber(Self.moved(activeWorkspaces(), fromOffsets: offsets, toOffset: destination))
        try context.save()
    }

    /// Hides `workspace` from everyday use. Its history stays.
    public func archive(_ workspace: Workspace) throws {
        guard !workspace.isArchived else { return }
        let rest = try activeWorkspaces().filter { $0.id != workspace.id }
        workspace.isArchived = true
        renumber(rest)
        try context.save()
    }

    /// Brings an archived `workspace` back, at the end of the active ones.
    public func restore(_ workspace: Workspace) throws {
        guard workspace.isArchived else { return }
        let active = try activeWorkspaces()
        workspace.isArchived = false
        renumber(active + [workspace])
        try context.save()
    }

    private func renumber(_ workspaces: [Workspace]) {
        for (index, workspace) in workspaces.enumerated() where workspace.sortOrder != index {
            workspace.sortOrder = index
        }
    }

    /// `base` when no name in `taken` equals it, otherwise `base` followed by
    /// the lowest number from 2 that makes it free, such as `New workspace 2`.
    public static func uniqueName(base: String, taken: [String]) -> String {
        let taken = Set(taken)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") {
            number += 1
        }
        return "\(base) \(number)"
    }

    /// The first palette color not in `used`, or the first color when all are used.
    public static func firstUnusedColor(used: [WorkspaceColor]) -> WorkspaceColor {
        WorkspaceColor.allCases.first { !used.contains($0) } ?? .teal
    }

    /// The quick start number key of the active workspace at `position`,
    /// counted from 0, or `nil` when it has none.
    public static func quickStartKey(at position: Int) -> Int? {
        (0 ..< quickStartKeyCount).contains(position) ? position + 1 : nil
    }

    /// The block lengths to offer when `minutes` is stored: the usual
    /// ``blockLengthChoices``, with `minutes` added in its place when it is not
    /// one of them, so a stored value is always shown and never lost.
    public static func blockLengthChoices(including minutes: Int) -> [Int] {
        blockLengthChoices.contains(minutes) ? blockLengthChoices : (blockLengthChoices + [minutes]).sorted()
    }

    /// `items` with the elements at `offsets` moved to before `destination`.
    ///
    /// Offsets outside `items` are ignored, and `destination` is clamped to
    /// the list.
    public static func moved<Element>(
        _ items: [Element],
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
    ) -> [Element] {
        let offsets = offsets.filteredIndexSet { items.indices.contains($0) }
        let moving = offsets.map { items[$0] }
        var rest = items.indices.filter { !offsets.contains($0) }.map { items[$0] }
        let destination = min(max(destination, 0), items.count)
        rest.insert(contentsOf: moving, at: destination - offsets.count(in: 0 ..< destination))
        return rest
    }
}
