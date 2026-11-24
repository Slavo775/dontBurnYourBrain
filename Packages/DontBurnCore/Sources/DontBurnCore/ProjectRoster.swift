import Foundation
import SwiftData

/// Creates, orders, archives and restores the projects of a workspace.
///
/// A project is never deleted: its blocks and entries name it. Removing one
/// archives it instead. The active projects of each workspace keep a dense
/// ``SchemaV1/Project/sortOrder`` from 0. A project is renamed and its time
/// tracking switched through its properties and a save of the context, which
/// changes nothing on the blocks and entries that already name it. Every
/// operation here saves the context.
public struct ProjectRoster {
    private let context: ModelContext

    /// A roster working on the projects in `context`.
    public init(context: ModelContext) {
        self.context = context
    }

    /// The active projects of `workspace` among `projects`, in their order.
    public static func active(_ projects: [Project], in workspace: Workspace) -> [Project] {
        projects
            .filter { !$0.isArchived && $0.workspace?.id == workspace.id }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The archived projects of `workspace` among `projects`, by name.
    public static func archived(_ projects: [Project], in workspace: Workspace) -> [Project] {
        projects
            .filter { $0.isArchived && $0.workspace?.id == workspace.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Adds a project at the end of the active projects of `workspace` and returns it.
    ///
    /// It is named `baseName`, or `baseName` with a number when a project of
    /// `workspace`, archived ones included, already has that name. Its time is
    /// tracked.
    @discardableResult
    public func create(baseName: String, in workspace: Workspace) throws -> Project {
        let own = try projects(of: workspace)
        let project = Project(
            name: WorkspaceRoster.uniqueName(base: baseName, taken: own.map(\.name)),
            workspace: workspace,
        )
        context.insert(project)
        renumber(Self.active(own, in: workspace) + [project])
        try context.save()
        return project
    }

    /// Moves the active projects of `workspace` at `offsets` to before
    /// `destination`, as a list's drag and drop reports it.
    public func move(in workspace: Workspace, fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        let active = try Self.active(projects(of: workspace), in: workspace)
        renumber(WorkspaceRoster.moved(active, fromOffsets: offsets, toOffset: destination))
        try context.save()
    }

    /// Hides `project` from everyday use. Its blocks, entries and folders stay.
    public func archive(_ project: Project) throws {
        guard !project.isArchived else { return }
        let rest = try project.workspace.map { try Self.active(projects(of: $0), in: $0) } ?? []
        project.isArchived = true
        renumber(rest.filter { $0.id != project.id })
        try context.save()
    }

    /// Brings an archived `project` back, at the end of its workspace's active projects.
    public func restore(_ project: Project) throws {
        guard project.isArchived else { return }
        let active = try project.workspace.map { try Self.active(projects(of: $0), in: $0) } ?? []
        project.isArchived = false
        renumber(active + [project])
        try context.save()
    }

    /// Every project of `workspace`, archived ones included.
    private func projects(of workspace: Workspace) throws -> [Project] {
        // Filtered here rather than in a predicate through the optional
        // relationship: a workspace holds a handful of projects.
        try context.fetch(FetchDescriptor<Project>()).filter { $0.workspace?.id == workspace.id }
    }

    private func renumber(_ projects: [Project]) {
        for (index, project) in projects.enumerated() where project.sortOrder != index {
            project.sortOrder = index
        }
    }
}
