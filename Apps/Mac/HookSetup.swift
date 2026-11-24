import DontBurnCore
import Foundation
import Observation
import os

/// The Claude Code profiles on this Mac and whether each has the hook, for
/// the Sessions tab.
///
/// The Release build looks for profiles in the home folder and may install
/// into any of them. The Dev build never looks at the real home folder: it
/// looks only in the stand-in folder its launch argument names, installs only
/// into settings files inside it, and offers the lines for a scratch project
/// for every other profile. Nothing is read until ``refresh()``.
@MainActor
@Observable
final class HookSetup {
    /// The defaults key of the profile folders added by hand. The defaults
    /// belong to this Mac and are never synced.
    static let addedFoldersKey = "ClaudeProfileFolders"

    /// Whether this is the Dev build.
    let isDev: Bool
    /// The installer, or `nil` when no hook can be written, as ``installerError`` says.
    let installer: HookInstaller?
    /// Why there is no installer, or `nil` when there is one.
    let installerError: HookInstallError?
    /// The profiles found and added, as of the last ``refresh()``.
    private(set) var profiles: [ClaudeProfile] = []
    /// Each profile's hook, as of the last ``refresh()``. Empty without an installer.
    private(set) var statuses: [ClaudeProfile.ID: HookStatus] = [:]

    /// Where profiles are looked for, or `nil` for nowhere.
    private let home: String?
    /// The folder settings files may be read and written in, as
    /// ``HookInstaller/init(command:directory:allowedFolder:)`` takes it.
    private let allowedFolder: String?
    private let defaults: UserDefaults
    /// Whether the profiles are a fixed sample, which ``refresh()`` keeps.
    private var isSample = false
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "hook")

    init(
        isDev: Bool,
        home: String?,
        allowedFolder: String?,
        installer: Result<HookInstaller, HookInstallError>,
        defaults: UserDefaults,
    ) {
        self.isDev = isDev
        self.home = home
        self.allowedFolder = allowedFolder
        self.defaults = defaults
        switch installer {
        case let .success(installer):
            self.installer = installer
            installerError = nil
        case let .failure(error):
            self.installer = nil
            installerError = error
        }
    }

    /// The setup of this build, with `standIn` from the Dev build's
    /// `-DontBurnStandInHome` launch argument.
    static func current(standIn: String?) -> HookSetup {
        let isDev = isDevBuild
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let folder = isDev ? standIn.flatMap { ProfileStandIn.folder(from: $0, home: realHome) } : "/"
        return HookSetup(
            isDev: isDev,
            home: isDev ? folder : realHome,
            allowedFolder: folder,
            installer: makeInstaller(isDev: isDev, allowedFolder: folder),
            defaults: .standard,
        )
    }

    /// Whether this is the Dev build: the Debug configuration, or a build that says it is Dev.
    ///
    /// A build whose variant is unknown counts as Release elsewhere. Here it
    /// counts as Dev when it was built for Debug, so no Debug build ever
    /// writes into a real profile.
    private static var isDevBuild: Bool {
        #if DEBUG
            true
        #else
            BuildInfo.current.variant == .dev
        #endif
    }

    private static func makeInstaller(isDev: Bool, allowedFolder: String?) -> Result<HookInstaller, HookInstallError> {
        let tool = Bundle.main.bundleURL.appending(path: "Contents/Helpers/dontburn-hook").path(percentEncoded: false)
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              FileManager.default.isExecutableFile(atPath: tool)
        else { return .failure(.toolMissing) }
        do {
            let command = try HookCommand(toolPath: tool, target: isDev ? .dev : .release)
            let directory = StoreLocation.directory(
                bundleIdentifier: bundleIdentifier,
                applicationSupport: .applicationSupportDirectory,
            )
            return .success(HookInstaller(command: command, directory: directory, allowedFolder: allowedFolder))
        } catch {
            return .failure(error as? HookInstallError ?? .unsafeToolPath)
        }
    }

    /// The lines to add or take out by hand, or `nil` without an installer.
    var manualLines: String? {
        installer.map { HookSettings.manualLines(command: $0.command.text) }
    }

    /// The lines for a scratch project, in the Dev build when it has no
    /// stand-in folder or a profile lies outside it, otherwise `nil`.
    var scratchLines: String? {
        guard isDev, allowedFolder == nil || statuses.values.contains(.outOfReach) else { return nil }
        return manualLines
    }

    /// Looks for the profiles again, and reads each one's hook.
    func refresh() {
        guard !isSample else { return }
        let added = defaults.stringArray(forKey: Self.addedFoldersKey) ?? []
        profiles = ClaudeProfile.find(inHome: home, added: added, allowedFolder: allowedFolder)
        guard let installer else {
            statuses = [:]
            return
        }
        statuses = Dictionary(uniqueKeysWithValues: profiles.map { profile in
            (profile.id, profile.settingsFile.map(installer.status(ofSettingsFile:)) ?? .outOfReach)
        })
    }

    /// Adds the profile folders at `urls`, kept in this Mac's defaults.
    func add(_ urls: [URL]) {
        var added = defaults.stringArray(forKey: Self.addedFoldersKey) ?? []
        for path in urls.map({ $0.path(percentEncoded: false) }) where !added.contains(path) {
            added.append(path)
        }
        defaults.set(added, forKey: Self.addedFoldersKey)
        refresh()
    }

    /// The other profiles that share `profile`'s settings file.
    func sharers(of profile: ClaudeProfile) -> [ClaudeProfile] {
        profile.sharers(among: profiles)
    }

    /// The install into `profile`'s settings file, for the user to confirm.
    func plan(for profile: ClaudeProfile) -> Result<HookInstallPlan, HookInstallError> {
        guard let installer else { return .failure(installerError ?? .toolMissing) }
        guard let file = profile.settingsFile else { return .failure(.outsideAllowedFolder) }
        do {
            return try .success(installer.plan(forSettingsFile: file))
        } catch {
            return .failure(logged(error, action: "plan an install"))
        }
    }

    /// Writes `plan`, which the user confirmed.
    func install(_ plan: HookInstallPlan) -> HookInstallError? {
        defer { refresh() }
        guard let installer else { return installerError ?? .toolMissing }
        do {
            try installer.install(plan)
            log.info("Installed the hook")
            return nil
        } catch {
            return logged(error, action: "install the hook")
        }
    }

    /// Removes the hook from `profile`'s settings file.
    func uninstall(_ profile: ClaudeProfile) -> Result<HookUninstallResult, HookInstallError> {
        defer { refresh() }
        guard let installer else { return .failure(installerError ?? .toolMissing) }
        guard let file = profile.settingsFile else { return .failure(.outsideAllowedFolder) }
        do {
            let result = try installer.uninstall(settingsFile: file)
            log.info("Uninstalled the hook, identical: \(result.isIdentical, privacy: .public)")
            return .success(result)
        } catch {
            return .failure(logged(error, action: "uninstall the hook"))
        }
    }

    /// `error` as the installer's own, logged by its case alone: its context names a path.
    private func logged(_ error: any Error, action: StaticString) -> HookInstallError {
        let error = error as? HookInstallError ?? .writeFailed
        log.error("Could not \(action.description, privacy: .public): \(String(describing: error), privacy: .public)")
        return error
    }
}

extension HookSetup {
    /// Three sample profiles in no real folder, for previews: Acme and Globex
    /// share one settings file with the hook installed, and Personal has none.
    /// Its installer may touch no file.
    static var sample: HookSetup {
        let installer = Result<HookInstaller, any Error> {
            try HookInstaller(
                command: HookCommand(toolPath: Bundle.main.bundleURL.appending(path: "Contents/Helpers/dontburn-hook")
                    .path(percentEncoded: false), target: .release),
                directory: FileManager.default.temporaryDirectory,
                allowedFolder: nil,
            )
        }.mapError { _ in HookInstallError.unsafeToolPath }
        let setup = HookSetup(isDev: false, home: nil, allowedFolder: nil, installer: installer, defaults: .standard)
        let shared = "~/.claude-shared/settings.json"
        setup.profiles = [
            ClaudeProfile(folder: "~/.claude-acme", settingsFile: shared),
            ClaudeProfile(folder: "~/.claude-globex", settingsFile: shared),
            ClaudeProfile(folder: "~/.claude-personal", settingsFile: "~/.claude-personal/settings.json"),
        ]
        setup.isSample = true
        setup.statuses = [
            "~/.claude-acme": .installed,
            "~/.claude-globex": .installed,
            "~/.claude-personal": .notInstalled,
        ]
        return setup
    }
}
