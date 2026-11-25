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
    /// blocks after it. Nothing is running. The presets the app comes with are
    /// there too, and no workspace names one.
    public static func seed(into context: ModelContext, now: Date) throws {
        try FocusPreset.seedDefaults(into: context)
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

public extension SampleData {
    /// Adds finished entries on each of the 35 days before the day of `now`,
    /// which always hold last week and the month so far, so History has full
    /// weeks and a month to show.
    ///
    /// Weekdays hold Acme and Globex work with and without projects, an Acme
    /// break and on Mondays and Wednesdays a Globex meeting. Tuesday and
    /// Thursday evenings hold Personal work and a Personal break, which does
    /// not count. Saturday is empty, and Sunday holds a little Personal work.
    /// Three days back a Personal entry crosses midnight, and the latest
    /// weekday's first Acme entry has a note with a comma, quotes and a line
    /// break. Hours are read in `calendar`.
    ///
    /// Call it after ``seed(into:now:)``. An entry that would overlap one
    /// already there, or end in the three hours before `now`, where the sample
    /// set's own entries and the ``TimerScenario`` blocks lie, is left out.
    static func seedHistory(into context: ModelContext, now: Date, calendar: Calendar) throws {
        let workspaces = try Dictionary(
            context.fetch(FetchDescriptor<Workspace>()).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first },
        )
        guard let acme = workspaces["Acme"], let globex = workspaces["Globex"], let personal = workspaces["Personal"]
        else { return }
        let projects = try context.fetch(FetchDescriptor<Project>())
        let existing = try context.fetch(FetchDescriptor<TimeEntry>())
        let clearFrom = now.addingTimeInterval(-3 * 3600)
        let today = calendar.startOfDay(for: now)

        // Adds an entry from `time`, an hour and a minute of `day`, unless it is left out.
        @discardableResult
        func add(
            _ workspace: Workspace, _ projectName: String?, _ day: Date, _ time: (Int, Int), _ minutes: Int,
            kind: TimeEntryKind = .work, source: TimeEntrySource = .timer, note: String = "",
        ) throws -> Bool {
            guard let start = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day),
                  let end = calendar.date(byAdding: .minute, value: minutes, to: start),
                  end <= clearFrom,
                  !existing.contains(where: { $0.start < end && ($0.end ?? .distantFuture) > start })
            else { return false }
            let entry = TimeEntry(workspace: workspace, start: start, end: end, kind: kind, source: source, note: note)
            try entry.assign(projects.first { $0.name == projectName && $0.workspace === workspace })
            context.insert(entry)
            return true
        }

        // The most recent weekday's first entry gets the note a CSV file must quote.
        var note = "Checkout, \"the redirect\" again\nthen the notes"
        for back in 1 ... 35 {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            // 1 is Sunday and 7 Saturday, whatever the first weekday.
            let weekday = calendar.component(.weekday, from: day)
            if weekday == 1 {
                try add(personal, "Side project", day, (10, 0), 90)
            }
            if (2 ... 6).contains(weekday) {
                note = try add(acme, weekday % 2 == 0 ? "Web shop" : "Mobile app", day, (9, 0), 90, note: note)
                    ? "" : note
                try add(acme, nil, day, (10, 30), 15, kind: .break)
                try add(acme, nil, day, (10, 45), 90 - back % 3 * 15)
                if weekday == 2 || weekday == 4 {
                    try add(globex, nil, day, (13, 0), 30, kind: .meeting, source: .calendar)
                }
                try add(globex, "Data platform", day, (13, 30), 120 + back % 4 * 15)
                if weekday == 3 || weekday == 5 {
                    try add(personal, "Side project", day, (20, 0), 60)
                    try add(personal, nil, day, (21, 0), 15, kind: .break)
                }
            }
            if back == 3 {
                try add(personal, "Side project", day, (23, 15), 90, source: .manual)
            }
        }
        try context.save()
    }
}
