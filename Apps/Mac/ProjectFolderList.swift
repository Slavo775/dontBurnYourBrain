import DontBurnCore
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A project's folders on this Mac, each with a remove button, and "Add folder…".
///
/// Reads and writes the local store, which its environment holds.
struct ProjectFolderList: View {
    let project: Project
    /// Every project of every workspace, to name the one that holds a folder already.
    let projects: [Project]

    @Environment(\.modelContext) private var context
    @Query private var folders: [ProjectFolder]
    @State private var isPicking = false
    /// The folders just refused, with the project that holds each.
    @State private var refusals: [Refusal] = []

    private struct Refusal: Identifiable {
        let path: String
        let holder: String
        var id: String {
            path
        }
    }

    init(project: Project, projects: [Project]) {
        self.project = project
        self.projects = projects
        let id = project.id
        _folders = Query(filter: #Predicate<ProjectFolder> { $0.projectID == id }, sort: \.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(folders) { folder in
                let shown = displayPath(folder.path)
                // The folder's name first, the path below it, shortened in
                // the middle so its end stays, and whole in the tooltip.
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: folderName(folder.path))
                        Text(verbatim: shown)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    }
                    .lineLimit(1)
                    .help(shown)
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button {
                        remove(folder)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(shown)")
                }
            }
            Button("Add folder…") { isPicking = true }
            ForEach(refusals) { refusal in
                Text("“\(folderName(refusal.path))” already belongs to \(refusal.holder).")
                    .font(.callout)
                    .foregroundStyle(Color.bad)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(refusal.path)
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder], allowsMultipleSelection: true) {
            add($0)
        }
    }

    private func add(_ result: Result<[URL], any Error>) {
        refusals = []
        let urls: [URL]
        do {
            urls = try result.get()
        } catch {
            logError("Could not pick a folder: \(error.localizedDescription)")
            return
        }
        let store = ProjectFolders(context: context)
        for url in urls {
            let path = url.path(percentEncoded: false)
            do {
                try store.add(path, to: project, among: projects)
            } catch let ProjectFolderError.taken(name) {
                let holder = name.isEmpty ? String(localized: "Unnamed") : name
                refusals.append(Refusal(path: displayPath(path), holder: holder))
            } catch {
                logError("Could not add a folder: \(error.localizedDescription)")
            }
        }
    }

    private func remove(_ folder: ProjectFolder) {
        refusals = []
        do {
            try ProjectFolders(context: context).remove(folder)
        } catch {
            logError("Could not remove a folder: \(error.localizedDescription)")
        }
    }

    private func logError(_ message: String) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "projects").error("\(message)")
    }
}

/// `path` with the home folder written as `~`.
private func displayPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

/// The last part of `path`, the folder's own name.
private func folderName(_ path: String) -> String {
    (path as NSString).lastPathComponent
}

#Preview("Sample data") {
    let container = ModelContainer.sample
    if let container, let webShop = try? container.mainContext.fetch(FetchDescriptor<Project>(
        predicate: #Predicate { $0.name == "Web shop" },
    )).first, let folders = ModelContainer.sampleFolders(for: container) {
        ProjectFolderList(project: webShop, projects: [webShop])
            .modelContainer(folders)
            .frame(width: 260)
            .padding()
    }
}
