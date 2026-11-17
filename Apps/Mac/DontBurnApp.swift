import DontBurnCore
import SwiftUI

@main
struct DontBurnApp: App {
    @State private var ticker = Ticker(
        fixedTime: Self.launchArgument("DontBurnFixedTime").flatMap(FixedTime.date(from:)),
    )

    init() {
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
    private static func launchArgument(_ name: String) -> String? {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[name] as? String
    }

    var body: some Scene {
        MenuBarExtra {
            Button("Quit \(Bundle.main.displayName)") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            ClockLabel(ticker: ticker)
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
