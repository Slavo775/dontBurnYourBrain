import DontBurnCore
import SwiftUI
import UniformTypeIdentifiers

/// The Sessions tab: the Claude Code profiles with their hook, the other
/// agents, and the terminals Focus brings forward.
struct SessionsPane: View {
    let setup: HookSetup
    let terminalFocus: TerminalFocus

    @State private var isPicking = false
    @State private var sheet: SessionsSheet?

    var body: some View {
        Form {
            Section {
                if setup.profiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Claude Code profile found.")
                        Text("Add one by its folder, such as .claude in your home folder.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(setup.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        status: setup.statuses[profile.id],
                        sharers: setup.sharers(of: profile),
                        install: { askToInstall(profile) },
                        uninstall: { uninstall(profile) },
                    )
                }
                Button("Add a profile folder…") { isPicking = true }
            } header: {
                Text("Claude Code profiles")
            } footer: {
                Text("Sessions that are already running pick up the hook with their next prompt.")
                    .foregroundStyle(.secondary)
            }
            if let error = setup.installerError {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                }
            }
            if let lines = setup.scratchLines {
                Section("Dev build") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Dev build installs only into profiles in its stand-in folder.")
                        Text("To try the hook in a scratch project, add these lines to its .claude/settings.json.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    LinesView(text: lines)
                }
            }
            Section("Other agents") {
                HStack {
                    AgentIcon()
                    Text(verbatim: "Codex")
                    Spacer()
                    StatusChip(text: "added later", isPositive: false)
                }
            }
            TerminalsSection(terminalFocus: terminalFocus)
        }
        .formStyle(.grouped)
        .onAppear { setup.refresh() }
        .fileImporter(
            isPresented: $isPicking,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true,
        ) { result in
            // A cancelled or failed pick adds nothing.
            if let urls = try? result.get() {
                setup.add(urls)
            }
        }
        // Profile folders such as .claude are hidden.
        .fileDialogBrowserOptions(.includeHiddenFiles)
        .fileDialogDefaultDirectory(setup.pickerFolder)
        .sheet(item: $sheet) { sheet in
            SessionsSheetView(
                sheet: sheet,
                manualLines: setup.manualLines,
                close: { self.sheet = nil },
                install: install,
            )
        }
    }

    private func askToInstall(_ profile: ClaudeProfile) {
        switch setup.plan(for: profile) {
        case let .success(plan):
            let affected = [profile] + setup.sharers(of: profile)
            sheet = SessionsSheet(.confirm(plan, affected: affected.map(\.name)))
        case let .failure(error):
            sheet = SessionsSheet(.refused(error, file: profile.settingsFile ?? profile.folder, isUninstall: false))
        }
    }

    private func install(_ plan: HookInstallPlan) {
        sheet = nil
        if let error = setup.install(plan) {
            sheet = SessionsSheet(.refused(error, file: plan.settingsFile, isUninstall: false))
        }
    }

    private func uninstall(_ profile: ClaudeProfile) {
        let file = profile.settingsFile ?? profile.folder
        switch setup.uninstall(profile) {
        case let .success(result): sheet = SessionsSheet(.uninstalled(result, file: file))
        case let .failure(error): sheet = SessionsSheet(.refused(error, file: file, isUninstall: true))
        }
    }
}

/// One profile: its name, path and sharers, and its hook.
private struct ProfileRow: View {
    let profile: ClaudeProfile
    /// The hook, or `nil` when it cannot be told.
    let status: HookStatus?
    let sharers: [ClaudeProfile]
    let install: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AgentIcon()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: profile.name)
                Text(verbatim: displayPath(profile.folder))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .help(displayPath(profile.folder))
                if !sharers.isEmpty {
                    Text("Shares its settings file with \(sharers.map(\.name).formatted(.list(type: .and)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if status == .foundWithoutRecord {
                    Text("Added outside this app, so it is removed by hand.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            switch status {
            case .installed:
                StatusChip(text: "hook installed", isPositive: true)
                Button("Uninstall", action: uninstall)
            case .foundWithoutRecord:
                StatusChip(text: "hook installed", isPositive: true)
            case .notInstalled:
                Button("Install hook", action: install)
            case .outOfReach:
                StatusChip(text: "scratch project only", isPositive: false)
            case nil:
                EmptyView()
            }
        }
    }
}

/// The terminal tile in front of an agent's row.
struct AgentIcon: View {
    var body: some View {
        // Decoration: the row's text says what it is.
        Image(systemName: "terminal")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// A small status label, such as "hook installed".
struct StatusChip: View {
    let text: LocalizedStringKey
    let isPositive: Bool

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(isPositive ? Color.green : Color.secondary)
            .background(Capsule().fill(Color.sunken))
    }
}

/// JSON lines in a monospaced, selectable block.
private struct LinesView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
    }
}

/// What a sheet of the Sessions tab shows.
struct SessionsSheet: Identifiable {
    enum Content {
        /// An install to confirm, and the names of every profile it affects.
        case confirm(HookInstallPlan, affected: [String])
        /// An install or uninstall that was refused, for the settings file `file`.
        case refused(HookInstallError, file: String, isUninstall: Bool)
        /// An uninstall that was done.
        case uninstalled(HookUninstallResult, file: String)
    }

    let id = UUID()
    let content: Content

    init(_ content: Content) {
        self.content = content
    }
}

/// The confirmation before an install, a refusal with the lines to change by
/// hand, or what an uninstall left.
private struct SessionsSheetView: View {
    let sheet: SessionsSheet
    let manualLines: String?
    let close: () -> Void
    let install: (HookInstallPlan) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch sheet.content {
            case let .confirm(plan, affected): confirmation(plan, affected: affected)
            case let .refused(error, file, isUninstall): refusal(error, file: file, isUninstall: isUninstall)
            case let .uninstalled(result, file): uninstalled(result, file: file)
            }
        }
        .padding(20)
        .frame(width: 600, alignment: .leading)
    }

    @ViewBuilder
    private func confirmation(_ plan: HookInstallPlan, affected: [String]) -> some View {
        Text("Install the hook?")
            .font(.headline)
        LabeledContent("File") { Text(verbatim: displayPath(plan.settingsFile)) }
        LabeledContent("Profiles") { Text(verbatim: affected.formatted(.list(type: .and))) }
        Text("These lines change. Nothing else in the file does.")
            .foregroundStyle(.secondary)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(plan.changedLines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: "\(line.kind == .added ? "+" : "−") \(line.number)  \(line.text)")
                        .foregroundStyle(line.kind == .added ? Color.green : Color.bad)
                }
            }
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
            Button("Install") { install(plan) }
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func refusal(_ error: HookInstallError, file: String, isUninstall: Bool) -> some View {
        Group {
            if isUninstall {
                Text("The hook was not removed")
            } else {
                Text("The hook was not installed")
            }
        }
        .font(.headline)
        Text(error.message)
        LabeledContent("File") { Text(verbatim: displayPath(file)) }
        if error.offersManualLines, let manualLines {
            if isUninstall {
                Text("Take each group with this command out of the file by hand:")
            } else {
                Text("Add these entries to the file by hand:")
            }
            LinesView(text: manualLines)
        }
        HStack {
            Spacer()
            Button("OK", action: close)
                .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private func uninstalled(_ result: HookUninstallResult, file: String) -> some View {
        Text("The hook is removed")
            .font(.headline)
        LabeledContent("File") { Text(verbatim: displayPath(file)) }
        if result.isIdentical {
            Text("The file is byte for byte what it was before the install.")
        } else {
            Text("The file differs from before the install. The difference was kept.")
            if !result.differingKeys.isEmpty {
                Text("Keys that differ: \(result.differingKeys.formatted(.list(type: .and)))")
            }
            if result.wasReplaced {
                Text("Another file stands at this path since the install, so another app may have written it.")
            }
            if let backup = result.keptBackup {
                Text("The backup from before the install is kept at \(displayPath(backup)).")
                    .textSelection(.enabled)
            }
        }
        HStack {
            Spacer()
            Button("OK", action: close)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private extension HookInstallError {
    /// What the user reads about the error.
    var message: LocalizedStringKey {
        switch self {
        case .missing: "The profile has no settings.json."
        case .notAFile: "settings.json is not a file."
        case .unreadable: "settings.json could not be read."
        case .tooLarge: "settings.json is too large to edit safely."
        case .notJSONObject: "settings.json is not a JSON object."
        case .unusualFormatting: "settings.json is formatted in a way the app would change, so it is left as it is."
        case .hooksNotObjectOfLists: "The hooks in settings.json are not in the form Claude Code writes."
        case .hardLinked: "settings.json has another hard link, which a write would split from it."
        case .alreadyInstalled: "The hook is already in this file."
        case .notInstalled: "No install of the hook into this file is on record."
        case .outsideAllowedFolder: "The Dev build changes no settings file outside its stand-in folder."
        case .changedMeanwhile: "The file changed while it was being edited. Nothing was written. Try again."
        case .unsafeToolPath: "The app's path can't go into a hook command safely. Move the app to another folder."
        case .toolMissing: "The hook tool is missing from this copy of the app."
        case .writeFailed: "A file could not be written. settings.json is unchanged."
        }
    }
}

/// `path` with the home folder written as `~`.
private func displayPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

#Preview("Sample profiles") {
    SessionsPane(setup: .sample, terminalFocus: TerminalFocus(isSample: true))
        .frame(width: 760, height: 470)
}

#Preview("No profile") {
    SessionsPane(
        setup: HookSetup(
            isDev: true, home: nil, allowedFolder: nil, installer: .failure(.toolMissing), defaults: .standard,
        ),
        terminalFocus: TerminalFocus(isSample: true),
    )
    .frame(width: 760, height: 470)
}
