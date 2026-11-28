import DontBurnCore
import Foundation

extension BuildInfo {
    /// This build, read from the app's own bundle.
    static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// Whether this is the Dev build: the Debug configuration, or a build that says it is Dev.
    ///
    /// A build whose variant is unknown counts as Release elsewhere. Here it
    /// counts as Dev when it was built for Debug, so no Debug build ever
    /// writes into a real profile or registers a login item.
    static var isDevBuild: Bool {
        #if DEBUG
            true
        #else
            current.variant == .dev
        #endif
    }
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
