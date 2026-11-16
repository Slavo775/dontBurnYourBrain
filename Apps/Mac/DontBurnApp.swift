import DontBurnCore
import SwiftUI

@main
struct DontBurnApp: App {
    @State private var ticker = Ticker(
        fixedTime: UserDefaults.standard.string(forKey: "DontBurnFixedTime").flatMap(FixedTime.date(from:)),
    )

    init() {
        switch UserDefaults.standard.string(forKey: "DontBurnAppearance").flatMap(Appearance.init(rawValue:)) {
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case nil: break
        }
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
