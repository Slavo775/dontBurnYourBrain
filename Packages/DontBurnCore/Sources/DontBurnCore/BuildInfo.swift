/// What a build says about itself: version, build number, variant and commit.
///
/// Read from a bundle's info dictionary, which the build fills from
/// `project.yml`, so nothing here repeats the version or the variant.
public struct BuildInfo: Equatable, Sendable {
    /// Which of the two side-by-side builds this is.
    public enum Variant: String, Sendable {
        case dev = "Dev"
        case release = "Release"
    }

    /// The version for humans, such as `0.1.0`, or empty when the bundle has none.
    public let version: String
    /// The build number, such as `1`, or empty when the bundle has none.
    public let build: String
    /// The variant. A missing or unknown value counts as Release, so the daily
    /// copy never shows the Dev marker by mistake.
    public let variant: Variant
    /// The short commit hash the build was made from, or `nil` when it carries none.
    public let commit: String?

    /// Reads `CFBundleShortVersionString`, `CFBundleVersion`, `DontBurnVariant`
    /// and `DontBurnCommit` from `info`. Values that are not strings count as missing.
    public init(infoDictionary info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? ""
        build = info["CFBundleVersion"] as? String ?? ""
        variant = (info["DontBurnVariant"] as? String).flatMap(Variant.init(rawValue:)) ?? .release
        commit = (info["DontBurnCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}
