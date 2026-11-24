import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The Rhythm tab: the focus presets on the left, the chosen one's form on the right.
struct RhythmPane: View {
    @Environment(\.modelContext) private var context
    @Query(sort: PresetRoster.order) private var presets: [FocusPreset]
    @Query(sort: \Workspace.sortOrder) private var workspaces: [Workspace]

    @State private var selection: FocusPreset.ID?
    /// The preset the dialog asks about, by its name, because the dialog
    /// outlives the preset it removes.
    @State private var removalCandidate: PresetName?
    /// The preset whose name field takes the focus next, set on create.
    @State private var nameFocusRequest: FocusPreset.ID?

    private var roster: PresetRoster {
        PresetRoster(context: context)
    }

    private var selected: FocusPreset? {
        presets.first { $0.id == selection }
    }

    var body: some View {
        Group {
            if presets.isEmpty {
                ContentUnavailableView {
                    Label("No presets yet", systemImage: "clock")
                } description: {
                    Text("A preset splits a block into focus intervals and breaks.")
                } actions: {
                    Button("Create a preset", action: create)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 220)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil {
                selection = presets.first?.id
            }
        }
        .confirmationDialog(
            "Remove “\(removalCandidate?.name ?? "")”?",
            isPresented: Binding { removalCandidate != nil } set: { _ in removalCandidate = nil },
            presenting: removalCandidate,
        ) { candidate in
            Button("Remove", role: .destructive) { remove(candidate.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Blocks that already follow it keep their rhythm.")
        }
    }

    private var list: some View {
        List(presets, selection: $selection) { preset in
            Text(verbatim: PresetName(preset).name)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                bar
            }
        }
        // The sidebar material would otherwise run up under the tab bar.
        .clipped()
    }

    /// + and − under the list.
    private var bar: some View {
        HStack(spacing: 0) {
            Button(action: create) {
                Image(systemName: "plus")
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Add a preset")
            Button {
                removalCandidate = selected.map(PresetName.init)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove this preset")
            .disabled(selected.map { !names(using: $0).isEmpty } ?? true)
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            PresetForm(
                preset: selected,
                usedBy: names(using: selected),
                nameFocusRequest: $nameFocusRequest,
                save: save,
            )
            .id(selected.id)
        } else {
            Text("Choose a preset")
                .foregroundStyle(.secondary)
        }
    }

    /// The names of the workspaces that keep `preset` from being removed.
    private func names(using preset: FocusPreset) -> [String] {
        PresetRoster.workspaces(naming: preset, among: workspaces).map { workspace in
            let name = workspace.name.isEmpty ? String(localized: "Unnamed") : workspace.name
            return workspace.isArchived ? String(localized: "\(name) (archived)") : name
        }
    }

    private func create() {
        perform("create a preset") {
            let preset = try roster.create(baseName: String(localized: "New preset"))
            selection = preset.id
            nameFocusRequest = preset.id
        }
    }

    private func remove(_ id: FocusPreset.ID) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        perform("remove a preset") {
            let rest = presets.filter { $0.id != id }
            try roster.remove(presets[index])
            selection = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        }
    }

    private func save() {
        perform("save a preset") {
            try context.save()
        }
    }

    private func perform(_ action: StaticString, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "presets")
                .error("Could not \(action.description, privacy: .public): \(error.localizedDescription)")
        }
    }
}

/// The chosen preset's settings.
private struct PresetForm: View {
    let preset: FocusPreset
    /// The workspaces that keep it from being removed.
    let usedBy: [String]
    @Binding var nameFocusRequest: FocusPreset.ID?
    let save: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The same form as a workspace's.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    label("Name")
                    TextField("Name", text: value(\.name))
                        .labelsHidden()
                        .focused($isNameFocused)
                }
                GridRow {
                    label("Focus")
                    HStack {
                        NumberField("Focus minutes", value: value(\.focusMinutes), in: PresetRoster.minuteRange)
                        Text("min")
                    }
                }
                GridRow {
                    label("Break")
                    HStack {
                        NumberField("Break minutes", value: value(\.breakMinutes), in: PresetRoster.minuteRange)
                        Text("min")
                    }
                }
                GridRow {
                    label("Long break")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Long break", isOn: value(\.hasLongBreak))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        if preset.hasLongBreak {
                            HStack {
                                NumberField(
                                    "Long break minutes",
                                    value: value(\.longBreakMinutes),
                                    in: PresetRoster.minuteRange,
                                )
                                Text("min, after")
                                NumberField(
                                    "Rounds before the long break",
                                    value: value(\.roundsBeforeLongBreak),
                                    in: PresetRoster.roundRange,
                                )
                                Text("rounds")
                            }
                        }
                    }
                }
                GridRow {
                    label("After a break")
                    Picker("After a break", selection: value(\.resumesAfterBreak)) {
                        Text("Resume by itself").tag(true)
                        Text("Wait for me").tag(false)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .controlSize(.large)
            if !usedBy.isEmpty {
                Text("Used by \(usedBy.formatted(.list(type: .and))), so it can't be removed.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .onChange(of: nameFocusRequest, initial: true) {
            guard nameFocusRequest == preset.id else { return }
            nameFocusRequest = nil
            // A turn later, as for a new workspace: the form is being swapped in.
            Task { isNameFocused = true }
        }
    }

    /// A value of the preset, saved as soon as it is set. A number field sets
    /// its value when it loses the focus, which can be as its form goes away.
    private func value<Value>(_ path: ReferenceWritableKeyPath<FocusPreset, Value> & Sendable) -> Binding<Value> {
        Binding {
            preset[keyPath: path]
        } set: {
            preset[keyPath: path] = $0
            save()
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .trailing)
    }
}

/// A workspace's default rhythm, with its minutes below it, in the workspace's form.
struct WorkspaceRhythmPicker: View {
    @Bindable var workspace: Workspace

    @Query(sort: PresetRoster.order) private var presets: [FocusPreset]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Rhythm", selection: $workspace.focusPreset) {
                Text("None").tag(FocusPreset?.none)
                ForEach(presets) { preset in
                    Text(verbatim: PresetName(preset).name).tag(Optional(preset))
                }
            }
            .labelsHidden()
            .fixedSize()
            if let preset = workspace.focusPreset {
                Text("\(preset.focusMinutes) min focus, \(preset.breakMinutes) min break")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A number typed or stepped, brought into its range when it is edited.
private struct NumberField: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    init(_ title: LocalizedStringKey, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, value: edited, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Stepper(title) {
                value = PresetRoster.number(value, steppedBy: 1, in: range)
            } onDecrement: {
                value = PresetRoster.number(value, steppedBy: -1, in: range)
            }
        }
        .labelsHidden()
    }

    private var edited: Binding<Int> {
        Binding {
            value
        } set: {
            value = PresetRoster.number($0, replacing: value, in: range)
        }
    }
}

#Preview("Sample data") {
    if let container = ModelContainer.sample {
        RhythmPane()
            .modelContainer(container)
            .frame(width: 760, height: 470)
    }
}

#Preview("No presets") {
    // A preview without a store simply shows nothing.
    if let container = try? ModelStore.inMemory() {
        RhythmPane()
            .modelContainer(container)
            .frame(width: 760, height: 470)
    }
}
