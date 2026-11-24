import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The Workspaces tab: the list on the left, the chosen workspace on the right,
/// its settings or its projects.
struct WorkspacesPane: View {
    /// The open local store, or `nil` when it could not be opened.
    let localContainer: ModelContainer?

    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Workspace> { !$0.isArchived }, sort: \Workspace.sortOrder)
    private var active: [Workspace]
    @Query(filter: #Predicate<Workspace> { $0.isArchived }, sort: \Workspace.name)
    private var archived: [Workspace]

    @State private var selection: Workspace.ID?
    @State private var page = WorkspacePage.workspace
    @State private var showsArchived = true
    @State private var archiveCandidate: Workspace?
    /// The workspace whose name field takes the focus next, set on create.
    @State private var nameFocusRequest: Workspace.ID?

    private var roster: WorkspaceRoster {
        WorkspaceRoster(context: context)
    }

    private var selected: Workspace? {
        (active + archived).first { $0.id == selection }
    }

    private var archiveCandidateName: String {
        guard let archiveCandidate else { return "" }
        return archiveCandidate.name.isEmpty ? String(localized: "Unnamed") : archiveCandidate.name
    }

    var body: some View {
        Group {
            if active.isEmpty {
                NoWorkspacesView(archived: archived, create: create, restore: restore)
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
                selection = active.first?.id
            }
        }
        .confirmationDialog(
            "Archive “\(archiveCandidateName)”?",
            isPresented: Binding { archiveCandidate != nil } set: { _ in archiveCandidate = nil },
            presenting: archiveCandidate,
        ) { workspace in
            Button("Archive") { archive(workspace) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It leaves every menu, and its history stays. You can restore it from the Archived list.")
        }
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach(active) { workspace in
                    WorkspaceRow(workspace: workspace)
                }
                .onMove(perform: move)
            }
            if !archived.isEmpty {
                Section("Archived", isExpanded: $showsArchived) {
                    ForEach(archived) { workspace in
                        WorkspaceRow(workspace: workspace)
                            .opacity(0.5)
                    }
                }
            }
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
            .accessibilityLabel("Add a workspace")
            Button {
                archiveCandidate = selected
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Archive this workspace")
            .disabled(selected.map(\.isArchived) ?? true)
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            WorkspaceDetail(page: $page) {
                WorkspaceForm(
                    workspace: selected,
                    quickStartKey: active.firstIndex { $0.id == selected.id }
                        .flatMap(WorkspaceRoster.quickStartKey(at:)),
                    nameFocusRequest: $nameFocusRequest,
                    save: save,
                    restore: { restore(selected) },
                )
            } projects: {
                ProjectsPane(workspace: selected, localContainer: localContainer)
            }
            .id(selected.id)
        } else {
            Text("Choose a workspace")
                .foregroundStyle(.secondary)
        }
    }

    private func create() {
        perform("create a workspace") {
            let workspace = try roster.create(baseName: String(localized: "New workspace"))
            selection = workspace.id
            // Its name field is on the Workspace page.
            page = .workspace
            nameFocusRequest = workspace.id
        }
    }

    private func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        perform("move a workspace") {
            try roster.move(fromOffsets: offsets, toOffset: destination)
        }
    }

    private func archive(_ workspace: Workspace) {
        let index = active.firstIndex { $0.id == workspace.id } ?? 0
        perform("archive a workspace") {
            try roster.archive(workspace)
            let rest = active.filter { $0.id != workspace.id }
            selection = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        }
    }

    private func restore(_ workspace: Workspace) {
        perform("restore a workspace") {
            try roster.restore(workspace)
            selection = workspace.id
        }
    }

    private func save() {
        perform("save a workspace") {
            try context.save()
        }
    }

    private func perform(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "workspaces")
                .error("Could not \(action): \(error.localizedDescription)")
        }
    }
}

/// One workspace in the list: its color and its name.
private struct WorkspaceRow: View {
    let workspace: Workspace

    var body: some View {
        Label {
            if workspace.name.isEmpty {
                Text("Unnamed")
            } else {
                Text(verbatim: workspace.name)
            }
        } icon: {
            Circle()
                .fill(workspace.color.color)
                .frame(width: 10, height: 10)
        }
    }
}

/// The chosen workspace's settings. Read-only while it is archived.
private struct WorkspaceForm: View {
    @Bindable var workspace: Workspace
    let quickStartKey: Int?
    @Binding var nameFocusRequest: Workspace.ID?
    let save: () -> Void
    let restore: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if workspace.isArchived {
                HStack {
                    Label("Archived", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore", action: restore)
                }
            }
            // The prototype's form: a 130 pt column of muted, right-aligned
            // labels and 16 pt between rows. Later phases add Rhythm, Folders,
            // Jira, Round to, Breaks and Calendar between Default block and
            // Quick start.
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    label("Name")
                    TextField("Name", text: $workspace.name)
                        .labelsHidden()
                        .focused($isNameFocused)
                }
                GridRow {
                    label("Color")
                    ColorSwatches(selection: $workspace.color)
                }
                GridRow {
                    label("Default block")
                    Picker("Default block", selection: $workspace.defaultBlockMinutes) {
                        ForEach(
                            WorkspaceRoster.blockLengthChoices(including: workspace.defaultBlockMinutes),
                            id: \.self,
                        ) {
                            Text(blockLength($0)).tag($0)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if !workspace.isArchived {
                    GridRow {
                        label("Quick start")
                        Group {
                            if let quickStartKey {
                                Text("Shown on key \(quickStartKey)")
                            } else {
                                Text("No number key")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .controlSize(.large)
            .disabled(workspace.isArchived)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .onChange(of: workspace.name) { save() }
        .onChange(of: workspace.colorKey) { save() }
        .onChange(of: workspace.defaultBlockMinutes) { save() }
        .onChange(of: nameFocusRequest, initial: true) {
            guard nameFocusRequest == workspace.id else { return }
            nameFocusRequest = nil
            // Not in this update: the form is being swapped in and the list's
            // selection is changing, and focus set now ends on the sidebar
            // outline. A turn later the field is in the window, takes focus
            // and selects its text, so typing replaces the name.
            Task { isNameFocused = true }
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .trailing)
    }
}

/// A block length such as `25 min`, `1 h` or `1 h 30`, already localized.
func blockLength(_ minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 {
        return String(localized: "\(minutes) min")
    }
    if rest == 0 {
        return String(localized: "\(hours) h")
    }
    return String(localized: "\(hours) h \(String(format: "%02d", rest))")
}

/// The six palette colors as round buttons, the chosen one ringed.
private struct ColorSwatches: View {
    @Binding var selection: WorkspaceColor

    var body: some View {
        // 22 pt swatches 12 pt apart. The chosen one gets a 2 pt ring in its
        // own color, 2 pt out, as in the prototype.
        HStack(spacing: 8) {
            ForEach(WorkspaceColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 22, height: 22)
                        .padding(2)
                        .overlay {
                            if color == selection {
                                Circle().strokeBorder(color.color, lineWidth: 2)
                                    .padding(-2)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
        }
        // Line the row label up with the middle of the swatches.
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }
}

/// The pane when no workspace is active: an offer to create the first one,
/// and the archived ones, if any, with a way to restore each.
private struct NoWorkspacesView: View {
    let archived: [Workspace]
    let create: () -> Void
    let restore: (Workspace) -> Void

    var body: some View {
        VStack {
            ContentUnavailableView {
                Label("No workspaces yet", systemImage: "square.grid.2x2")
            } description: {
                Text("A workspace is one area of work, such as one client.")
            } actions: {
                Button("Create a workspace", action: create)
                    .buttonStyle(.borderedProminent)
            }
            if !archived.isEmpty {
                Form {
                    Section("Archived") {
                        ForEach(archived) { workspace in
                            LabeledContent {
                                Button("Restore") { restore(workspace) }
                            } label: {
                                WorkspaceRow(workspace: workspace)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(maxHeight: 220)
            }
        }
    }
}

#Preview("Sample data") {
    if let container = ModelContainer.sample {
        WorkspacesPane(localContainer: .sampleFolders(for: container))
            .modelContainer(container)
            .frame(width: 760, height: 470)
    }
}

#Preview("No workspaces") {
    // A preview without a store simply shows nothing.
    if let container = try? ModelStore.inMemory() {
        WorkspacesPane(localContainer: nil)
            .modelContainer(container)
            .frame(width: 760, height: 470)
    }
}
