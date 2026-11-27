import DontBurnCore
import os
import SwiftData
import SwiftUI

@main
struct DontBurnApp: App {
    private static let fixedTime = launchArgument("DontBurnFixedTime").flatMap(FixedTime.date(from:))

    /// The menu bar item, its panel and its menu. Kept for the life of the app.
    @State private var statusItem: StatusItemController
    /// The agent sessions, or `nil` without a bundle identifier. Kept for the life of the app.
    @State private var sessions: SessionMonitor?
    /// The Claude Code profiles and their hook, for Settings. Reads nothing until Settings shows it.
    @State private var hookSetup: HookSetup
    /// The question about time away, shared by the countdown and Settings.
    @State private var awaySettings: AwaySettings
    /// The command bar's shortcut, shared by the bar and Settings, or `nil` without a store.
    @State private var commandBarShortcut: CommandBarShortcut?

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
        // The sample data keeps its breaks and the question's settings in
        // memory, so a run with it leaves nothing in the defaults.
        let awaySettings = AwaySettings(
            defaults: sampleData ? nil : .standard,
            thresholdMinutes: Self.launchArgument("DontBurnAwayMinutes").flatMap(AwayStandIn.thresholdMinutes(from:)),
        )
        let idleCycle = Self.launchArgument("DontBurnSimulatedIdle").flatMap(AwayStandIn.idleCycle(from:))
        let countdown = Countdown(
            container: container,
            fixedTime: Self.fixedTime,
            alerts: AlertCenter(),
            defaults: sampleData ? nil : .standard,
            idleBreak: scenario?.idleBreak(at: now),
            awaySettings: awaySettings,
            idleTime: idleCycle.map { SimulatedIdleTime(launch: .now, cycle: $0) } ?? SystemIdleTime(),
            timeAway: scenario?.timeAway(at: now),
        )
        _awaySettings = State(initialValue: awaySettings)
        let mainWindow = MainWindowController(container: container, fixedTime: Self.fixedTime) {
            countdown.reschedule()
        }
        // Without a store there is nothing to act on, so no bar and no shortcut.
        let commandBar = container.map { _ in
            CommandBarController(countdown: countdown, shortcut: CommandBarShortcut(
                defaults: sampleData ? nil : .standard, isOnByDefault: Self.isShortcutOnByDefault,
            ))
        }
        _commandBarShortcut = State(initialValue: commandBar?.shortcut)
        _statusItem = State(initialValue: StatusItemController(
            countdown: countdown, mainWindow: mainWindow, commandBar: commandBar,
        ))
        _sessions = State(initialValue: Self.startSessions(sampleData: sampleData))
        _hookSetup = State(initialValue: HookSetup.current(standIn: Self.launchArgument("DontBurnStandInHome")))
        switch Self.launchArgument("DontBurnAppearance").flatMap(Appearance.init(rawValue:)) {
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
    }

    /// Whether the command bar's shortcut is on until it is switched: in the
    /// Release build only. Never in a Debug build, which is always Dev, so Dev
    /// takes no shortcut by default even when its variant is missing, which
    /// ``BuildInfo`` reads as Release.
    private static var isShortcutOnByDefault: Bool {
        #if DEBUG
            false
        #else
            BuildInfo.current.variant == .release
        #endif
    }

    /// The defaults key that remembers that the presets the app comes with were added.
    private static let presetsSeededKey = "presets.seeded"

    /// The value after `-<name>` on the command line, such as `-DontBurnAppearance dark`.
    ///
    /// Only the argument domain, so a value saved with `defaults write` never
    /// applies to every launch.
    ///
    /// Always `nil` outside the Debug configuration, so a Release build never
    /// runs a frozen clock, a forced appearance, the sample data, a stand-in
    /// home folder for the Claude Code profiles, or a short or simulated time away.
    static func launchArgument(_ name: String) -> String? {
        #if DEBUG
            UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
        #else
            nil
        #endif
    }

    /// The sample set in memory with `-DontBurnSampleData YES`, seeded at
    /// `now` with weeks of history before it, otherwise the store on disk in
    /// the folder named after the bundle identifier, with the presets the app
    /// comes with, added once.
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
                try SampleData.seedHistory(into: container.mainContext, now: now, calendar: .current)
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
            do {
                var isSeeded = UserDefaults.standard.bool(forKey: presetsSeededKey)
                try FocusPreset.seedDefaults(into: container.mainContext, isSeeded: &isSeeded)
                UserDefaults.standard.set(isSeeded, forKey: presetsSeededKey)
            } catch {
                // The timer works without presets, so the store stays open. The
                // rollback drops the unsaved presets, so no later save carries them.
                container.mainContext.rollback()
                log.error("The focus presets could not be added: \(error.localizedDescription)")
            }
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

    /// The sessions, listening on the hook channel in the folder named after
    /// the bundle identifier. With the sample data they stay in memory, and
    /// the channel is still opened.
    private static func startSessions(sampleData: Bool) -> SessionMonitor? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger(subsystem: "", category: "sessions")
                .error("No bundle identifier, so the hook channel has no folder of its own and is not opened")
            return nil
        }
        let applicationSupport = URL.applicationSupportDirectory
        let monitor = SessionMonitor(
            directory: sampleData
                ? nil
                : StoreLocation.directory(bundleIdentifier: bundleIdentifier, applicationSupport: applicationSupport),
            receiver: HookSocket(url: HookChannel.url(
                bundleIdentifier: bundleIdentifier, applicationSupport: applicationSupport,
            )),
        )
        monitor.start()
        return monitor
    }

    var body: some Scene {
        Settings {
            SettingsView(
                container: container, localContainer: localContainer, hookSetup: hookSetup, awaySettings: awaySettings,
                commandBarShortcut: commandBarShortcut,
            )
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
