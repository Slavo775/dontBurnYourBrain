@testable import DontBurnCore
import Foundation

/// Sessions fed by hook lines, and the projects whose folders hold them, by
/// folder. No store and no folder rule: a session is in the project its folder
/// names here, and in none otherwise.
struct SessionDesk {
    let acme = Workspace(name: "Acme", color: .teal)
    let globex = Workspace(name: "Globex", color: .indigo, sortOrder: 1)
    let personal = Workspace(name: "Personal", color: .ochre, sortOrder: 2)
    var projects: [String: Project]
    var replay = SessionReplay()

    init() {
        projects = [
            "/code/acme-web": Project(name: "Web shop", workspace: acme),
            "/code/acme-mobile": Project(name: "Mobile app", workspace: acme, sortOrder: 1),
            "/code/globex-data": Project(name: "Data platform", workspace: globex),
            "/code/reading-notes": Project(name: "Reading", workspace: personal, isTimeTracked: false),
        ]
    }

    /// Sends the event `name` of the session `id`, which runs in `folder`, at `seconds`.
    mutating func send(
        _ seconds: TimeInterval,
        _ name: String,
        _ id: String,
        in folder: String = "/code/acme-web",
        _ fields: [String: Any] = [:],
    ) throws {
        try replay.send(seconds, name, fields.merging(["cwd": folder]) { $1 }, session: id)
    }

    func list(at seconds: TimeInterval, filter: SessionFilter = .all) -> SessionList {
        SessionList(sessions: replay.store.sessions, filter: filter, at: HookLine.time(seconds)) {
            projects[$0.folder]
        }
    }
}

extension SessionList {
    /// Every row under the filter, in the order shown.
    var rows: [Row] {
        sections.flatMap(\.rows)
    }

    /// The ids of the rows in `group`, in order, or `nil` when the list leaves the group out.
    func ids(_ group: SessionGroup) -> [String]? {
        sections.first { $0.group == group }?.rows.map(\.id)
    }
}
