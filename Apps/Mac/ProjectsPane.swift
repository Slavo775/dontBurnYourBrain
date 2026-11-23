import DontBurnCore
import os
import SwiftData
import SwiftUI

/// Which page the Workspaces pane shows for the chosen workspace.
enum WorkspacePage: Hashable {
    case workspace
    case projects
}

/// The chosen workspace's side of the Workspaces pane: a Workspace | Projects
/// switch on top, and the page it picks below.
struct WorkspaceDetail<WorkspacePageView: View, ProjectsPageView: View>: View {
    @Binding var page: WorkspacePage
    let workspace: WorkspacePageView
    let projects: ProjectsPageView

    init(
        page: Binding<WorkspacePage>,
        @ViewBuilder workspace: () -> WorkspacePageView,
        @ViewBuilder projects: () -> ProjectsPageView,
    ) {
        _page = page
        self.workspace = workspace()
        self.projects = projects()
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Page", selection: $page) {
                Text("Workspace").tag(WorkspacePage.workspace)
                Text("Projects").tag(WorkspacePage.projects)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 12)
            switch page {
            case .workspace: workspace
            case .projects: projects
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The Projects page of a workspace: its project list on the left, the chosen
/// project on the right. Read-only while the workspace is archived.
struct ProjectsPane: View {
    let workspace: Workspace
    /// The open local store, or `nil` when it could not be opened.
    let localContainer: ModelContainer?

    @Environment(\.modelContext) private var context
    /// Every project of every workspace: a folder is checked against all of them.
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var selection: Project.ID?
    @State private var showsArchived = true
    /// The project whose name field takes the focus next, set on create.
    @State private var nameFocusRequest: Project.ID?

    private var roster: ProjectRoster {
        ProjectRoster(context: context)
    }

    private var active: [Project] {
        ProjectRoster.active(projects, in: workspace)
    }

    private var archived: [Project] {
        ProjectRoster.archived(projects, in: workspace)
    }

    private var selected: Project? {
        (active + archived).first { $0.id == selection }
    }

    var body: some View {
        Group {
            if active.isEmpty, archived.isEmpty {
                NoProjectsView(canCreate: !workspace.isArchived, create: create)
            } else {
                HStack(spacing: 0) {
                    list
                        .frame(width: 170)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selection == nil {
                selection = active.first?.id ?? archived.first?.id
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach(active) { project in
                    ProjectRow(project: project)
                        .moveDisabled(workspace.isArchived)
                }
                .onMove(perform: move)
            }
            if !archived.isEmpty {
                Section("Archived", isExpanded: $showsArchived) {
                    ForEach(archived) { project in
                        ProjectRow(project: project)
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
            .accessibilityLabel("Add a project")
            .disabled(workspace.isArchived)
            Button {
                if let selected {
                    archive(selected)
                }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Archive this project")
            .disabled(workspace.isArchived || (selected.map(\.isArchived) ?? true))
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detail: some View {
        if let selected {
            ProjectForm(
                project: selected,
                isWorkspaceArchived: workspace.isArchived,
                projects: projects,
                localContainer: localContainer,
                nameFocusRequest: $nameFocusRequest,
                save: save,
                restore: { restore(selected) },
            )
            .id(selected.id)
        } else {
            Text("Choose a project")
                .foregroundStyle(.secondary)
        }
    }

    private func create() {
        perform("create a project") {
            let project = try roster.create(baseName: String(localized: "New project"), in: workspace)
            selection = project.id
            nameFocusRequest = project.id
        }
    }

    private func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        perform("move a project") {
            try roster.move(in: workspace, fromOffsets: offsets, toOffset: destination)
        }
    }

    private func archive(_ project: Project) {
        let index = active.firstIndex { $0.id == project.id } ?? 0
        perform("archive a project") {
            try roster.archive(project)
            let rest = active.filter { $0.id != project.id }
            selection = rest.isEmpty ? project.id : rest[min(index, rest.count - 1)].id
        }
    }

    private func restore(_ project: Project) {
        perform("restore a project") {
            try roster.restore(project)
            selection = project.id
        }
    }

    private func save() {
        perform("save a project") {
            try context.save()
        }
    }

    private func perform(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "projects")
                .error("Could not \(action): \(error.localizedDescription)")
        }
    }
}

/// One project in the list: its name.
private struct ProjectRow: View {
    let project: Project

    var body: some View {
        if project.name.isEmpty {
            Text("Unnamed")
        } else {
            Text(verbatim: project.name)
        }
    }
}

/// The chosen project's settings. Read-only while it or its workspace is archived.
private struct ProjectForm: View {
    @Bindable var project: Project
    let isWorkspaceArchived: Bool
    /// Every project of every workspace.
    let projects: [Project]
    let localContainer: ModelContainer?
    @Binding var nameFocusRequest: Project.ID?
    let save: () -> Void
    let restore: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if project.isArchived {
                HStack {
                    Label("Archived", systemImage: "archivebox")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isWorkspaceArchived {
                        Button("Restore", action: restore)
                    }
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    label("Name")
                    TextField("Name", text: $project.name)
                        .labelsHidden()
                        .focused($isNameFocused)
                }
                GridRow {
                    label("Track time")
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Track time", isOn: $project.isTimeTracked)
                            .labelsHidden()
                            .toggleStyle(.switch)
                        Text("Time already tracked stays when this is off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    label("Folders")
                    if let localContainer {
                        ProjectFolderList(project: project, projects: projects)
                            .modelContainer(localContainer)
                    } else {
                        Text("The folders could not be opened.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isWorkspaceArchived || project.isArchived)
            Spacer(minLength: 0)
        }
        .padding(16)
        .onChange(of: project.name) { save() }
        .onChange(of: project.isTimeTracked) { save() }
        .onChange(of: nameFocusRequest, initial: true) {
            guard nameFocusRequest == project.id else { return }
            nameFocusRequest = nil
            // A turn later, as in the workspace form: the form is being
            // swapped in, and focus set now ends on the list.
            Task { isNameFocused = true }
        }
    }

    private func label(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .trailing)
    }
}

/// The Projects page of a workspace that has none: one line, and a way to
/// create the first unless the workspace is archived.
private struct NoProjectsView: View {
    let canCreate: Bool
    let create: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("This workspace has no projects.")
                .foregroundStyle(.secondary)
            if canCreate {
                Button("Create a project", action: create)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Projects page of the sample Acme, with the sample folders or without a local store.
@MainActor
private func projectsPreview(withLocalStore: Bool) -> some View {
    let container = ModelContainer.sample
    let acme = try? container?.mainContext.fetch(FetchDescriptor<Workspace>(
        predicate: #Predicate { $0.name == "Acme" },
    )).first
    return Group {
        if let container, let acme {
            ProjectsPane(workspace: acme, localContainer: withLocalStore ? .sampleFolders(for: container) : nil)
                .modelContainer(container)
                .frame(width: 539, height: 420)
        }
    }
}

#Preview("Sample data") {
    projectsPreview(withLocalStore: true)
}

#Preview("No local store") {
    projectsPreview(withLocalStore: false)
}
