import Foundation
import SwiftData

/// The neutral sample set for previews, tests and screenshots: Acme, Globex and Personal.
public enum SampleData {
    /// Whether a launch argument's value turns the sample data on, such as `YES` in `-DontBurnSampleData YES`.
    ///
    /// The value is input from outside the app. Only `YES`, `true` and `1`,
    /// in any case, turn it on. Anything else, or no value, leaves it off.
    public static func isRequested(by raw: String?) -> Bool {
        guard let raw, raw.utf8.count <= 4 else { return false }
        return ["yes", "true", "1"].contains(raw.lowercased())
    }

    /// Inserts the sample set into `context` and saves it.
    ///
    /// Every block and entry is placed relative to `now`: finished entries in
    /// the hours before it, one manual entry a day before it, and planned
    /// blocks after it. Nothing is running.
    public static func seed(into context: ModelContext, now: Date) throws {
        func minutes(_ value: Int) -> Date {
            now.addingTimeInterval(TimeInterval(value * 60))
        }

        let acme = Workspace(name: "Acme", color: .teal, sortOrder: 0)
        let globex = Workspace(name: "Globex", color: .indigo, sortOrder: 1)
        let personal = Workspace(name: "Personal", color: .ochre, sortOrder: 2)
        personal.breaksCount = false

        let webShop = Project(name: "Web shop", workspace: acme)
        let mobileApp = Project(name: "Mobile app", workspace: acme, sortOrder: 1)
        let dataPlatform = Project(name: "Data platform", workspace: globex)
        let sideProject = Project(name: "Side project", workspace: personal)
        let reading = Project(name: "Reading", workspace: personal, isTimeTracked: false, sortOrder: 1)

        let acmeBlock = TimeBlock(workspace: acme, plannedStart: minutes(-180), plannedMinutes: 90, state: .done)
        try acmeBlock.assign(webShop)
        let globexBlock = TimeBlock(workspace: globex, plannedStart: minutes(30), plannedMinutes: 60)
        try globexBlock.assign(dataPlatform)
        let personalBlock = TimeBlock(workspace: personal, plannedStart: minutes(120), plannedMinutes: 45)
        try personalBlock.assign(sideProject)

        let work = TimeEntry(workspace: acme, start: minutes(-180), end: minutes(-130), block: acmeBlock)
        try work.assign(webShop)
        let pause = TimeEntry(workspace: acme, start: minutes(-130), end: minutes(-120), kind: .break, block: acmeBlock)
        let moreWork = TimeEntry(workspace: acme, start: minutes(-120), end: minutes(-90), block: acmeBlock)
        try moreWork.assign(webShop)
        // Ends an hour before `now`, so no ``TimerScenario`` block, which
        // starts at most an hour before it, overlaps the meeting.
        let meeting = TimeEntry(
            workspace: globex, start: minutes(-90), end: minutes(-60), kind: .meeting, source: .calendar,
        )
        // A day earlier, so History has something to show. A day before
        // `now` and more is always before today's midnight.
        let day = 24 * 60
        let manual = TimeEntry(
            workspace: acme, start: minutes(-day - 300), end: minutes(-day - 240), source: .manual,
            note: "Release checklist",
        )
        try manual.assign(mobileApp)

        let models: [any PersistentModel] = [
            acme, globex, personal,
            webShop, mobileApp, dataPlatform, sideProject, reading,
            acmeBlock, globexBlock, personalBlock,
            work, pause, moreWork, meeting, manual,
        ]
        for model in models {
            context.insert(model)
        }
        try context.save()
    }

    /// The sample projects' folders, below the sample root, by project name.
    ///
    /// `acme-web/mobile` lies inside `acme-web`, so the deepest folder's
    /// project, Mobile app, wins there. Reading has no folder.
    public static let folders = [
        "Web shop": ["code/acme-web"],
        "Mobile app": ["code/acme-mobile", "code/acme-web/mobile"],
        "Data platform": ["code/globex-data"],
        "Side project": ["code/side-project"],
    ]

    /// Makes the sample ``folders`` on disk below `root` and gives them to the
    /// sample projects in `projects`, recording them in `context`, a context
    /// of the local store.
    ///
    /// Pass a temporary `root`, so no real folder ever shows, and a local store
    /// in memory, so nothing reaches the store on disk.
    public static func seedFolders(into context: ModelContext, projects: ModelContext, root: URL) throws {
        let all = try projects.fetch(FetchDescriptor<Project>())
        let store = ProjectFolders(context: context)
        for project in all {
            for folder in folders[project.name] ?? [] {
                let url = root.appending(path: folder, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try store.add(url.path(percentEncoded: false), to: project, among: all)
            }
        }
    }
}
