import DontBurnCore
import Foundation

extension BuildInfo {
    /// This build, read from the app's own bundle.
    static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
}

extension BuildInfo.Variant {
    /// The variant's name for the interface.
    var name: String {
        switch self {
        case .dev: String(localized: "Dev")
        case .release: String(localized: "Release")
        }
    }
}
