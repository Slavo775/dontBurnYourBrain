import Foundation

/// Why a block or an entry may not name a project.
public enum ProjectAssignmentError: Error, Equatable, Sendable {
    /// The project's time is not tracked.
    case notTimeTracked
    /// The project belongs to another workspace, or the block or entry has none.
    case otherWorkspace
}

public extension Project {
    /// Checks that a block or an entry in `workspace` may name this project.
    ///
    /// The project must belong to `workspace` and its time must be tracked.
    func checkAssignable(to workspace: Workspace?) throws(ProjectAssignmentError) {
        guard let workspace, let own = self.workspace, own.id == workspace.id else {
            throw .otherWorkspace
        }
        guard isTimeTracked else { throw .notTimeTracked }
    }
}

public extension TimeBlock {
    /// Names `project` for this block, or clears it with `nil`.
    ///
    /// Throws, and leaves the block as it was, when the project is not
    /// assignable to the block's workspace.
    func assign(_ project: Project?) throws(ProjectAssignmentError) {
        try project?.checkAssignable(to: workspace)
        self.project = project
    }
}

public extension TimeEntry {
    /// Names `project` for this entry, or clears it with `nil`.
    ///
    /// Throws, and leaves the entry as it was, when the project is not
    /// assignable to the entry's workspace.
    func assign(_ project: Project?) throws(ProjectAssignmentError) {
        try project?.checkAssignable(to: workspace)
        self.project = project
    }
}
