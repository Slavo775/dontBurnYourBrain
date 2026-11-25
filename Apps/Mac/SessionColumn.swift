import DontBurnCore
import Foundation
import Observation
import os
import SwiftData

/// What the expanded panel's session column shows, renewed while it is shown.
///
/// It follows the events as they come, and once a second it looks again: a
/// turn that stopped becomes idle, an idle row's minutes count up, and a
/// session whose process is gone leaves. Nothing runs while it is not shown.
@MainActor
@Observable
final class SessionColumn {
    /// The sessions, as of the last look.
    private(set) var list = SessionList(sessions: [], at: .distantPast) { _ in nil }

    /// Why the list is empty, as of the moment the column was shown. A
    /// session that has shown since proves that a hook is there.
    private(set) var noSessions = NoSessions.noneRunning

    /// Whether the panel shows the column: it is open and expanded.
    var isShown = false {
        didSet {
            if isShown != oldValue {
                shownChanged()
            }
        }
    }

    private let monitor: SessionMonitor?
    private let projects: ModelContext?
    private let folders: ModelContext?
    private let fixedTime: Date?
    /// Reads the hook of each profile.
    private let readHooks: () -> [HookStatus]
    @ObservationIgnored private var timer: Timer?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "sessions")

    /// The sessions of `monitor`, or none without it, with their projects from
    /// `container` and the folders in `localContainer`. Without either store
    /// every session is listed under Other.
    ///
    /// `readHooks` runs only when the column is shown and there is no session,
    /// once each time. With `fixedTime` the list is the one of that instant.
    init(
        monitor: SessionMonitor?,
        container: ModelContainer?,
        localContainer: ModelContainer?,
        fixedTime: Date?,
        readHooks: @escaping () -> [HookStatus],
    ) {
        self.monitor = monitor
        projects = container?.mainContext
        folders = localContainer?.mainContext
        self.fixedTime = fixedTime
        self.readHooks = readHooks
        monitor?.onEvent = { [weak self] in
            if self?.isShown == true {
                self?.look()
            }
        }
    }

    /// Shows the sessions under `filter`.
    func show(_ filter: SessionFilter) {
        look(filter: filter)
    }

    private func shownChanged() {
        timer?.invalidate()
        timer = nil
        guard isShown else { return }
        look()
        if list.isEmpty {
            noSessions = NoSessions(hooks: readHooks())
        }
        guard fixedTime == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        // Common modes, so it keeps looking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func look(filter: SessionFilter? = nil) {
        let new = makeList(filter: filter ?? list.filter, at: fixedTime ?? .now)
        if new != list {
            list = new
        }
        if !new.isEmpty {
            noSessions = .noneRunning
        }
    }

    private func makeList(filter: SessionFilter, at now: Date) -> SessionList {
        let sessions = monitor?.currentSessions() ?? []
        if let projects, let folders {
            do {
                let all = try projects.fetch(FetchDescriptor<Project>())
                let holders = ProjectFolders(context: folders)
                return try SessionList(sessions: sessions, filter: filter, at: now) {
                    try $0.project(in: holders, among: all)
                }
            } catch {
                // The error may name a path, so only its code is logged.
                log.error("The sessions' projects could not be read, error \((error as NSError).code)")
            }
        }
        return SessionList(sessions: sessions, filter: filter, at: now) { _ in nil }
    }
}
