import DontBurnCore
import os
import SwiftData
import SwiftUI

@main
struct DontBurnApp: App {
    private static let fixedTime = launchArgument("DontBurnFixedTime").flatMap(FixedTime.date(from:))

    @State private var countdown: Countdown

    /// The open store, or `nil` when it could not be opened.
    private let container: ModelContainer?

    init() {
        let sampleData = SampleData.isRequested(by: Self.launchArgument("DontBurnSampleData"))
        let container = Self.openStore(sampleData: sampleData)
        self.container = container
        _countdown = State(initialValue: Countdown(container: container, fixedTime: Self.fixedTime))
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

    /// The sample set in memory with `-DontBurnSampleData YES`, otherwise the
    /// store on disk in the folder named after the bundle identifier.
    ///
    /// With the sample set, `-DontBurnTimerState <scenario>` also puts the
    /// timer into one of the ``TimerScenario`` states. It is ignored without
    /// the sample set, so it never changes the store on disk.
    ///
    /// The sample data never touches the store on disk. A store that cannot be
    /// opened is logged, and the app keeps running without one.
    private static func openStore(sampleData: Bool) -> ModelContainer? {
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "store")
        do {
            if sampleData {
                let container = try ModelStore.inMemory()
                let now = fixedTime ?? .now
                try SampleData.seed(into: container.mainContext, now: now)
                if let scenario = TimerScenario(launchArgument: launchArgument("DontBurnTimerState")) {
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

    var body: some Scene {
        MenuBarExtra {
            OpenSettingsButton()
            Divider()
            Button("Quit \(Bundle.main.displayName)") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            MenuBarItemLabel(countdown: countdown)
        }
        Settings {
            SettingsView(container: container)
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
