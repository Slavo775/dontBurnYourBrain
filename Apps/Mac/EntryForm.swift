import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The sheet that corrects an entry or adds one by hand: start, end,
/// workspace, kind and note. A refused change shows the sentence that says why.
struct EntryForm: View {
    /// What the form does.
    enum Mode: Identifiable {
        /// Adds a manual entry on the day that contains the date.
        case add(day: Date)
        /// Corrects a stored entry.
        case edit(TimeEntry)

        var id: AnyHashable {
            switch self {
            case let .add(day): day
            case let .edit(entry): entry.persistentModelID
            }
        }
    }

    let mode: Mode
    let context: ModelContext
    let fixedTime: Date?
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft
    @State private var refusal: String?

    init(mode: Mode, context: ModelContext, fixedTime: Date?, onChange: @escaping () -> Void) {
        self.mode = mode
        self.context = context
        self.fixedTime = fixedTime
        self.onChange = onChange
        let now = fixedTime ?? .now
        switch mode {
        case let .edit(entry):
            _draft = State(initialValue: EntryDraft(entry, now: now))
        case let .add(day):
            _draft = State(initialValue: Self.newDraft(on: day, now: now, context: context))
        }
    }

    private var entry: TimeEntry? {
        if case let .edit(entry) = mode {
            entry
        } else {
            nil
        }
    }

    private var isNoteOnly: Bool {
        entry.map(EntryEditor.isNoteOnly) ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if isNoteOnly {
                    Label(
                        "This entry's block is still running. Only its note can change until the block ends.",
                        systemImage: "lock",
                    )
                    .foregroundStyle(Color.muted)
                }
                Group {
                    DatePicker("Start", selection: $draft.start, displayedComponents: [.date, .hourAndMinute])
                    if entry?.end == nil, entry != nil {
                        LabeledContent("End", value: String(localized: "Running"))
                    } else {
                        DatePicker("End", selection: $draft.end, displayedComponents: [.date, .hourAndMinute])
                    }
                    Picker("Workspace", selection: $draft.workspace) {
                        ForEach(workspaceChoices) { workspace in
                            let name = workspace.name
                            (workspace.isArchived ? Text("\(name) (archived)") : Text(verbatim: name))
                                .tag(Optional(workspace))
                        }
                    }
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(EntryEditor.kindChoices(keeping: entry?.kind), id: \.self) { kind in
                            Text(kind.name).tag(kind)
                        }
                    }
                }
                .disabled(isNoteOnly)
                // A prompt, so the one field a running entry keeps reads as editable when empty.
                TextField("Note", text: $draft.note, prompt: Text("Add a note"))
                if let refusal {
                    Text(refusal)
                        .foregroundStyle(Color.bad)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(entry == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 440)
        .navigationTitle(entry == nil ? "Add entry" : "Edit entry")
    }

    /// The active workspaces, and the entry's own when it is archived.
    private var workspaceChoices: [Workspace] {
        // An empty list only leaves the picker empty, and saving then says to choose a workspace.
        let active = (try? WorkspaceRoster(context: context).activeWorkspaces()) ?? []
        return EntryEditor.workspaceChoices(active: active, keeping: entry?.workspace)
    }

    private func save() {
        let editor = EntryEditor(context: context)
        let now = fixedTime ?? .now
        do {
            if let entry {
                try editor.update(entry, to: draft, at: now)
            } else {
                try editor.add(draft, at: now)
            }
            onChange()
            dismiss()
        } catch let error as EntryChangeError {
            refusal = error.sentence
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "entries")
                .error("Could not save an entry: \(error.localizedDescription)")
            refusal = String(localized: "The entry could not be saved.")
        }
    }

    /// A work entry in the first active workspace: the half hour up to now on
    /// today, or 9:00 to 10:00 on an earlier day.
    private static func newDraft(on day: Date, now: Date, context: ModelContext) -> EntryDraft {
        let calendar = Calendar.current
        // No workspace only leaves the picker empty, and saving then says to choose one.
        let workspace = (try? WorkspaceRoster(context: context).activeWorkspaces())?.first
        if calendar.isDate(day, inSameDayAs: now) {
            let end = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            return EntryDraft(start: end.addingTimeInterval(-30 * 60), end: end, workspace: workspace)
        }
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        return EntryDraft(start: start, end: start.addingTimeInterval(3600), workspace: workspace)
    }
}

#Preview {
    if let container = ModelContainer.sample {
        let now = Date(timeIntervalSince1970: 1_768_466_490)
        EntryForm(mode: .add(day: now), context: container.mainContext, fixedTime: now, onChange: {})
    }
}
