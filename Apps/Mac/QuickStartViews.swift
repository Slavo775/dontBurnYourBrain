import DontBurnCore
import SwiftUI

/// Which view the panel shows, and the custom block form's choices. The
/// panel's keys change it too, so it lives outside the view.
@MainActor
@Observable
final class PanelNavigation {
    enum Page {
        /// The running block, or the quick start list when nothing runs.
        case main
        /// "Switch to", while a block runs.
        case switching
        /// The custom block form, while nothing runs.
        case customBlock
        /// "Break for", the break's lengths, while working or with nothing running.
        case breakLength
    }

    var page = Page.main

    /// Whether the panel is wide, with the sessions beside the block. It stays
    /// so until it is collapsed, also while the panel is closed.
    var isExpanded = false {
        didSet { onExpandedChange?() }
    }

    /// Called when ``isExpanded`` was set.
    @ObservationIgnored var onExpandedChange: (() -> Void)?

    /// The custom block's workspace. Choosing one preselects its default length and rhythm.
    var customWorkspace: Workspace? {
        didSet {
            if let customWorkspace, customWorkspace != oldValue {
                customMinutes = customWorkspace.defaultBlockMinutes
                customPreset = customWorkspace.focusPreset?.id
            }
        }
    }

    /// The custom block's length in minutes.
    var customMinutes = WorkspaceRoster.defaultBlockMinutes

    /// The preset the custom block follows, or `nil` for none.
    var customPreset: FocusPreset.ID?

    /// Opens the custom block form with the first of `workspaces` chosen.
    func openCustomBlock(_ workspaces: [Workspace]) {
        customWorkspace = workspaces.first
        customMinutes = workspaces.first?.defaultBlockMinutes ?? WorkspaceRoster.defaultBlockMinutes
        customPreset = workspaces.first?.focusPreset?.id
        page = .customBlock
    }

    /// Starts the custom block on `countdown` and returns to the main page.
    func startCustomBlock(with countdown: Countdown) {
        guard let customWorkspace else { return }
        page = .main
        countdown.start(customWorkspace, minutes: customMinutes, presetID: customPreset)
    }

    /// Break, on its button or on B: starts the planned break that is due,
    /// opens "Break for" where a break can start, and ends the running break.
    func takeBreak(with countdown: Countdown) {
        let state = countdown.state
        if let minutes = countdown.panel?.dueBreakMinutes {
            countdown.startPlannedBreak(minutes: minutes)
        } else if QuickAction.canStartBreak(in: state) {
            page = .breakLength
        } else if QuickAction.breakOrEndBreak.isAvailable(in: state) {
            countdown.perform(.breakOrEndBreak)
        }
    }

    /// Starts a break of `minutes` on `countdown` and returns to the main page.
    func startBreak(minutes: Int, with countdown: Countdown) {
        page = .main
        countdown.startBreak(minutes: minutes)
    }
}

/// One row per active workspace, with its number key, to start a block for it.
///
/// Titled "Switch to", with Back, while a block or a break runs, and "Nothing
/// running", with "Custom block" and "Take a break", while nothing runs. With
/// nothing running and more than nine workspaces the rows scroll; the first nine fit.
struct WorkspaceList: View {
    let title: LocalizedStringKey
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        let isSwitching = countdown.panel != nil
        PanelTitle(title) {
            if isSwitching {
                PanelBackButton { navigation.page = .main }
            } else {
                ExpandButton(navigation: navigation)
            }
        }

        let workspaces = countdown.workspaces
        let rows = VStack(spacing: 8) {
            ForEach(Array(workspaces.enumerated()), id: \.element.id) { position, workspace in
                Button {
                    navigation.page = .main
                    countdown.start(workspace)
                } label: {
                    StartRow(key: WorkspaceRoster.quickStartKey(at: position).map { "\($0)" }) {
                        WorkspaceDot(color: workspace.color)
                        HStack(spacing: 4) {
                            Text(workspace.name)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(blockLength(workspace.defaultBlockMinutes))
                                .foregroundStyle(Color.muted)
                                .fixedSize()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if !isSwitching, !workspaces.isEmpty {
                Button {
                    navigation.openCustomBlock(workspaces)
                } label: {
                    StartRow(key: "⌘N", isGhost: true) {
                        Text("Custom block")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
            }
            if !isSwitching, countdown.hasStore {
                TakeABreakRow(navigation: navigation)
            }
        }

        if !isSwitching, workspaces.count > WorkspaceRoster.quickStartKeyCount {
            // Nine rows of 56 pt and their gaps: the first nine fit, the rest
            // scroll. "Switch to" never scrolls, as design.md says.
            ScrollView {
                rows
            }
            .frame(height: 9 * 56 + 8 * 8)
        } else {
            rows
        }
    }
}

/// "Take a break" on the key B, while nothing runs: opens "Break for". It needs no workspace.
struct TakeABreakRow: View {
    let navigation: PanelNavigation

    var body: some View {
        Button {
            navigation.page = .breakLength
        } label: {
            StartRow(key: "B", isGhost: true) {
                Text("Take a break")
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(.plain)
    }
}

/// "Break for": one row per break length on the keys 1 to 4, with Back. The
/// last length used is preselected, and Return starts it; the panel's keys
/// handle both.
struct BreakLengthList: View {
    let countdown: Countdown
    let navigation: PanelNavigation

    var body: some View {
        PanelTitle("Break for") {
            PanelBackButton { navigation.page = .main }
        }

        VStack(spacing: 8) {
            ForEach(Array(TimerEngine.breakLengthChoices.enumerated()), id: \.element) { position, minutes in
                let isPreselected = minutes == countdown.breakMinutes
                Button {
                    navigation.startBreak(minutes: minutes, with: countdown)
                } label: {
                    StartRow(key: "\(position + 1)", isDefault: isPreselected) {
                        Text("\(minutes) min")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(minutes) minutes")
                .accessibilityAddTraits(isPreselected ? .isSelected : [])
            }
        }
    }
}

/// A sunken row: its content on the left and a key on the right. A ghost row
/// is outlined instead of filled, for a quieter, secondary action. The default
/// row, the one Return starts, gets a 2 pt ink outline and the Return key
/// beside its own, so it stands out by shape, not by colour alone.
struct StartRow<Content: View>: View {
    let key: String?
    var isGhost = false
    var isDefault = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            // Its own stack, so a Spacer inside the content pushes to the row's edge.
            HStack(spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            if isDefault || key != nil {
                // Return to the left, so the number keys stay in one column.
                HStack(spacing: 6) {
                    if isDefault {
                        KeyCap("↵")
                    }
                    if let key {
                        KeyCap(key)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: isGhost ? 44 : 56)
        .background(isGhost ? Color.clear : Color.sunken, in: .rect(cornerRadius: 12))
        .overlay {
            if isDefault {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink, lineWidth: 2)
            } else if isGhost {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line)
            }
        }
        .contentShape(.rect(cornerRadius: 12))
    }
}

/// A key shown beside a row, such as a number key, as the prototype's `m-key`.
/// VoiceOver skips it, because the row says what it does.
private struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(verbatim: key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(Color.keyBackground, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.line)
            }
            .accessibilityHidden(true)
    }
}

/// The custom block form: a workspace, a length and a rhythm, then Start.
/// Without any preset there is no rhythm to choose. Return starts, Escape goes
/// back to the list; the panel's keys handle both.
struct CustomBlockForm: View {
    let countdown: Countdown
    @Bindable var navigation: PanelNavigation

    var body: some View {
        PanelTitle("Custom block") {
            PanelBackButton { navigation.page = .main }
        }

        VStack(spacing: 8) {
            StartRow(key: nil) {
                Text("Workspace")
                    .foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                Picker("Workspace", selection: $navigation.customWorkspace) {
                    ForEach(countdown.workspaces) { workspace in
                        Text(workspace.name).tag(Optional(workspace))
                    }
                }
                .labelsHidden()
                .buttonStyle(.borderless)
                // As wide as the name, and cut off rather than wider than the panel.
                .buttonSizing(.fitted)
            }
            StartRow(key: nil) {
                Text("Length")
                    .foregroundStyle(Color.muted)
                Spacer(minLength: 0)
                Picker("Length", selection: $navigation.customMinutes) {
                    ForEach(WorkspaceRoster.blockLengthChoices(including: navigation.customMinutes), id: \.self) {
                        Text(blockLength($0)).tag($0)
                    }
                }
                .labelsHidden()
                .buttonStyle(.borderless)
                .fixedSize()
            }
            if !countdown.presets.isEmpty {
                StartRow(key: nil) {
                    Text("Rhythm")
                        .foregroundStyle(Color.muted)
                    Spacer(minLength: 0)
                    Picker("Rhythm", selection: $navigation.customPreset) {
                        Text("None").tag(FocusPreset.ID?.none)
                        ForEach(countdown.presets) { preset in
                            Text(verbatim: preset.name).tag(Optional(preset.id))
                        }
                    }
                    .labelsHidden()
                    .buttonStyle(.borderless)
                    .buttonSizing(.fitted)
                }
            }
        }

        Button("Start") {
            navigation.startCustomBlock(with: countdown)
        }
        .buttonStyle(PanelWideButtonStyle())
        .disabled(navigation.customWorkspace == nil)
    }
}

/// With a store but no workspace: says so, and leads to Settings. A break
/// needs no workspace, so "Take a break" is offered here too.
struct NoWorkspaces: View {
    let navigation: PanelNavigation

    var body: some View {
        PanelTitle("Nothing running") {
            ExpandButton(navigation: navigation)
        }
        // The prototype's note, as in its "Day off" panel.
        VStack(alignment: .leading, spacing: 2) {
            Text("No workspaces yet")
                .fontWeight(.semibold)
            Text("Add a workspace in Settings to start a block.")
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sunken, in: .rect(cornerRadius: 12))
        TakeABreakRow(navigation: navigation)
        OpenSettingsButton()
            .buttonStyle(PanelWideButtonStyle())
    }
}

/// The prototype's wide dark button (`m-btn go wide`): ink on the surface,
/// so the panel keeps the workspace colour as its only strong one.
private struct PanelWideButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.surface)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.ink.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
