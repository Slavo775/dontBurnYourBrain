import Foundation

/// Which build this is, read from the bundle.
///
/// A build phase in `project.yml` writes `DontBurnVariant` from the `APP_VARIANT`
/// build setting, and in the Dev build `DontBurnCommit` from git, so nothing
/// here is decided in code.
enum BuildVariant: String {
    case dev = "Dev"
    case release = "Release"

    /// This build's variant. A bundle without the key counts as Release, so a
    /// missing key never shows the Dev marker on the daily copy.
    static let current = Bundle.main.object(forInfoDictionaryKey: "DontBurnVariant")
        .flatMap { $0 as? String }
        .flatMap(BuildVariant.init(rawValue:)) ?? .release

    /// The short commit hash the build was made from, or `nil` when it carries none.
    static let commit = (Bundle.main.object(forInfoDictionaryKey: "DontBurnCommit") as? String)
        .flatMap { $0.isEmpty ? nil : $0 }

    /// The variant's name for the interface.
    var name: String {
        switch self {
        case .dev: String(localized: "Dev")
        case .release: String(localized: "Release")
        }
    }
}
