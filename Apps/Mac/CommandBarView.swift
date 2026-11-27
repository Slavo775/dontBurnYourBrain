import DontBurnCore
import SwiftData
import SwiftUI

/// The command bar: one field, the results for what was typed, and two lines
/// that say what else can be typed and which keys act at once.
struct CommandBarView: View {
    @Bindable var model: CommandBarModel
    /// Takes the result at the index, as Return does.
    let take: (Int) -> Void

    var body: some View {
        let results = model.results
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.muted)
                    .accessibilityHidden(true)
                TextField("Command", text: $model.text, prompt: Text("Type a workspace or a command"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 20))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            if !model.text.isEmpty {
                BarLine()
                if results.isEmpty {
                    Text("No match")
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }
                ForEach(Array(results.enumerated()), id: \.offset) { index, result in
                    Button { take(index) } label: {
                        ResultRow(
                            result: result,
                            isSelected: index == model.selection,
                            hasFailed: index == model.failedSelection,
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            BarLine()
            BarHints(example: example, hasQuickStarts: !model.quickStarts.isEmpty)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ink)
        .frame(width: 580)
        .background(Color.surface, in: .rect(cornerRadius: 16))
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ring)
        }
    }

    /// A start to show as an example, such as `acme 1h`, from the first workspace's first word.
    private var example: String? {
        model.quickStarts.first?.name.split(whereSeparator: \.isWhitespace).first.map { "\($0.lowercased()) 1h" }
    }
}

/// One result: what it does, and why it cannot when it cannot. The selected
/// one has the sunken background and the Return key.
private struct ResultRow: View {
    let result: BarResult
    let isSelected: Bool
    let hasFailed: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(reason == nil ? Color.ink : Color.muted)
                    .lineLimit(1)
                if let reason {
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected, reason == nil {
                KeyCap("↵")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(isSelected ? Color.sunken : Color.clear)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reason.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var icon: some View {
        if case let .start(workspace, _) = result.action {
            WorkspaceDot(color: workspace.color)
        } else {
            Image(systemName: symbol)
                .foregroundStyle(Color.muted)
        }
    }

    private var symbol: String {
        switch result.action {
        case .start: "circle"
        case .pause: "pause"
        case .resume: "play"
        case .startBreak, .plannedBreak, .endBreak: "cup.and.heat.waves"
        case .extend: "plus"
        case .endBlock: "stop"
        }
    }

    private var title: String {
        switch result.action {
        case let .start(workspace, minutes): String(localized: "Start \(workspace.name) for \(blockLength(minutes))")
        case .pause: String(localized: "Pause")
        case .resume: String(localized: "Resume")
        case let .startBreak(minutes): String(localized: "Break for \(blockLength(minutes))")
        case let .plannedBreak(minutes): String(localized: "Break now, \(blockLength(minutes))")
        case .endBreak: String(localized: "End break")
        case .extend: String(localized: "Add 15 minutes")
        case .endBlock: String(localized: "End block")
        }
    }

    private var reason: String? {
        if hasFailed {
            return String(localized: "This can't be done right now.")
        }
        return switch result.refusal {
        case nil: nil
        case .nothingRunning: String(localized: "Nothing is running.")
        case .paused: String(localized: "The block is paused. Resume first.")
        case .notPaused: String(localized: "Nothing is paused.")
        case .onBreak: String(localized: "A break is already running.")
        case .noBlock: String(localized: "No block is running.")
        case .tooLong: String(localized: "A break can't be longer than a day.")
        }
    }
}

/// What else can be typed, and the keys that act at once with the field empty.
private struct BarHints: View {
    /// A start to show, such as `acme 1h`, or `nil` without workspaces.
    let example: String?
    let hasQuickStarts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("You can also type")
                ForEach([example, "break 10", "+15", "pause", "end"].compactMap(\.self), id: \.self) {
                    Chip(text: $0)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            if hasQuickStarts {
                BarLine()
                HStack(spacing: 8) {
                    Text("Or press one key while the field is empty")
                    KeyCap("1–3")
                    Text("start a workspace")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Something to type, as the prototype's `m-code`.
private struct Chip: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.keyBackground, in: .rect(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.line)
            }
    }
}

/// The 1 pt line between the bar's parts.
private struct BarLine: View {
    var body: some View {
        Color.line.frame(height: 1)
    }
}

@MainActor
private func previewModel(_ text: String) -> CommandBarModel {
    let countdown = Countdown(container: .sample, fixedTime: Date(timeIntervalSince1970: 1_768_466_490))
    let model = CommandBarModel(countdown: countdown)
    model.text = text
    return model
}

#Preview("Empty") {
    CommandBarView(model: previewModel("")) { _ in }
}

#Preview("A result") {
    CommandBarView(model: previewModel("ac 2h")) { _ in }
}

#Preview("Refused") {
    CommandBarView(model: previewModel("end")) { _ in }
}

#Preview("No match") {
    CommandBarView(model: previewModel("xyz")) { _ in }
}
