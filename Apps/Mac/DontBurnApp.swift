import DontBurnCore
import os
import SwiftData
import SwiftUI

@main
struct DontBurnApp: App {
    private static let fixedTime = launchArgument("DontBurnFixedTime").flatMap(FixedTime.date(from:))

    /// The menu bar item, its panel and its menu. Kept for the life of the app.
    @State private var statusItem: StatusItemController

    /// The open store, or `nil` when it could not be opened.
    private let container: ModelContainer?
    /// The open local store, this Mac's own, or `nil` when it could not be opened.
    private let localContainer: ModelContainer?

    init() {
        let sampleData = SampleData.isRequested(by: Self.launchArgument("DontBurnSampleData"))
        // Ignored without the sample set, so it never changes the store on disk.
        let scenario = sampleData ? TimerScenario(launchArgument: Self.launchArgument("DontBurnTimerState")) : nil
        let now = Self.fixedTime ?? .now
        let container = Self.openStore(sampleData: sampleData, scenario: scenario, now: now)
        self.container = container
        localContainer = Self.openLocalStore(sampleData: sampleData, sampleProjects: container)
        // The sample data keeps its breaks in memory, so a run with it leaves nothing in the defaults.
        let countdown = Countdown(
            container: container,
            fixedTime: Self.fixedTime,
            alerts: AlertCenter(),
            defaults: sampleData ? nil : .standard,
            idleBreak: scenario?.idleBreak(at: now),
        )
        let mainWindow = MainWindowController(container: container, fixedTime: Self.fixedTime) {
            countdown.reschedule()
        }
        _statusItem = State(initialValue: StatusItemController(countdown: countdown, mainWindow: mainWindow))
        switch Self.launchArgument("DontBurnAppearance").flatMap(Appearance.init(rawValue:)) {
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
    }

    /// The value after `-<name>` on the command line, such as `-DontBurnAppearance dark`.
    ///
    /// Only the argument domain, so a value saved with `defaults write` never
    /// applies to every launch.
    ///
    /// Always `nil` outside the Debug configuration, so a Release build never
    /// runs a frozen clock, a forced appearance or the sample data.
    private static func launchArgument(_ name: String) -> String? {
        #if DEBUG
            UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
        #else
            nil
        #endif
    }

    /// The sample set in memory with `-DontBurnSampleData YES`, seeded at
    /// `now`, otherwise the store on disk in the folder named after the bundle
    /// identifier.
    ///
    /// With the sample set, `scenario`, from `-DontBurnTimerState <scenario>`,
    /// also puts the timer into one of the ``TimerScenario`` states.
    ///
    /// The sample data never touches the store on disk. A store that cannot be
    /// opened is logged, and the app keeps running without one.
    private static func openStore(sampleData: Bool, scenario: TimerScenario?, now: Date) -> ModelContainer? {
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "store")
        do {
            if sampleData {
                let container = try ModelStore.inMemory()
                try SampleData.seed(into: container.mainContext, now: now)
                if let scenario {
                    try scenario.apply(to: container.mainContext, now: now)
                    log.info("Put the sample timer into the \(scenario.rawValue) state")
                }
                let count = try container.mainContext.fetchCount(FetchDescriptor<Workspace>())
                log.info("Opened the sample data in memory, \(count) workspaces")
                return container
            }
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                log.error("No bundle identifier, so the store has no folder of its own and is not opened")
                return nil
            }
            let directory = StoreLocation.directory(
                bundleIdentifier: bundleIdentifier,
                applicationSupport: .applicationSupportDirectory,
            )
            let container = try ModelStore.onDisk(in: directory)
            log.info("Opened the store in its own folder")
            return container
        } catch {
            log.error("The store could not be opened: \(error.localizedDescription)")
            return nil
        }
    }

    /// The local store in memory with `-DontBurnSampleData YES`, holding the
    /// sample folders for the projects in `sampleProjects`, otherwise the local
    /// store on disk next to the synced one.
    ///
    /// The sample folders are made in a temporary folder named after the bundle
    /// identifier, so no real folder shows. A local store that cannot be opened
    /// is logged, and the app keeps running without one: projects still work,
    /// without their folders.
    private static func openLocalStore(sampleData: Bool, sampleProjects: ModelContainer?) -> ModelContainer? {
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "store")
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            log.error("No bundle identifier, so the local store has no folder of its own and is not opened")
            return nil
        }
        do {
            if sampleData {
                let container = try ModelStore.localInMemory()
                if let sampleProjects {
                    let root = FileManager.default.temporaryDirectory
                        .appending(path: "\(bundleIdentifier).sample", directoryHint: .isDirectory)
                    try SampleData.seedFolders(
                        into: container.mainContext, projects: sampleProjects.mainContext, root: root,
                    )
                }
                log.info("Opened the sample folders in memory")
                return container
            }
            let directory = StoreLocation.directory(
                bundleIdentifier: bundleIdentifier,
                applicationSupport: .applicationSupportDirectory,
            )
            let container = try ModelStore.localOnDisk(in: directory)
            log.info("Opened the local store in its own folder")
            return container
        } catch {
            log.error("The local store could not be opened: \(error.localizedDescription)")
            return nil
        }
    }

    var body: some Scene {
        Settings {
            SettingsView(container: container, localContainer: localContainer)
        }
    }
}

extension Bundle {
    /// The name the bundle gives the app, so the Dev build names itself as Dev.
    var displayName: String {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ""
    }
}
