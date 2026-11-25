import DontBurnCore
import os
import SwiftData
import SwiftUI

/// One day's entries and totals, with Add, Edit, Split and Delete. Today, or
/// in History an earlier day chosen with a picker and previous and next.
struct DayView: View {
    let context: ModelContext
    let fixedTime: Date?
    let isHistory: Bool
    let onChange: () -> Void

    /// The day shown in History. Today ignores it.
    @Binding private var historyDay: Date
    @State private var form: EntryForm.Mode?
    @State private var splitting: TimeEntry?
    @State private var deleting: TimeEntry?
    @State private var deleteError: EntryChangeError?

    /// Today with no `historyDay`, otherwise History on that day.
    init(context: ModelContext, fixedTime: Date?, historyDay: Binding<Date>?, onChange: @escaping () -> Void) {
        self.context = context
        self.fixedTime = fixedTime
        isHistory = historyDay != nil
        self.onChange = onChange
        _historyDay = historyDay ?? .constant(DayLog.day(before: fixedTime ?? .now, calendar: .current))
    }

    private var now: Date {
        fixedTime ?? .now
    }

    var body: some View {
        // Every second, so the running entry and the totals count up.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = fixedTime ?? timeline.date
            let day = isHistory ? historyDay : now
            content(day: day, now: now)
        }
        .navigationTitle(isHistory ? "History" : "Today")
        .toolbar {
            if isHistory {
                ToolbarItemGroup {
                    Button("Previous day", systemImage: "chevron.left") {
                        historyDay = DayLog.day(before: historyDay, calendar: .current)
                    }
                    DatePicker(
                        "Day",
                        selection: Binding(
                            get: { historyDay },
                            set: { historyDay = Calendar.current.startOfDay(for: $0) },
                        ),
                        in: ...DayLog.day(before: now, calendar: .current),
                        displayedComponents: .date,
                    )
                    .labelsHidden()
                    Button("Next day", systemImage: "chevron.right") {
                        if let next = DayLog.earlierDay(after: historyDay, now: now, calendar: .current) {
                            historyDay = next
                        }
                    }
                    .disabled(DayLog.earlierDay(after: historyDay, now: now, calendar: .current) == nil)
                }
            }
            ToolbarItem {
                Button("Add entry", systemImage: "plus") {
                    form = .add(day: isHistory ? historyDay : now)
                }
            }
        }
        .sheet(item: $form) { mode in
            EntryForm(mode: mode, context: context, fixedTime: fixedTime, onChange: onChange)
        }
        .sheet(item: $splitting) { entry in
            SplitForm(entry: entry, context: context, fixedTime: fixedTime, onChange: onChange)
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(get: { deleting != nil }, set: {
                if !$0 {
                    deleting = nil
                }
            }),
            presenting: deleting,
        ) { entry in
            Button("Delete", role: .destructive) {
                delete(entry)
            }
        } message: { entry in
            Text("\(entry.workspace?.name ?? "") \(timeRange(entry.start, entry.end ?? now)) is removed for good.")
        }
        .alert(
            "The entry was not deleted",
            isPresented: Binding(get: { deleteError != nil }, set: {
                if !$0 {
                    deleteError = nil
                }
            }),
            presenting: deleteError,
        ) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.sentence)
        }
    }

    @ViewBuilder
    private func content(day: Date, now: Date) -> some View {
        // A failed read shows a note instead of the list; the log has the reason.
        if let log = try? DayLog(day: day, in: context, now: now, calendar: .current) {
            VStack(alignment: .leading, spacing: 0) {
                DayTotals(log: log)
                    .padding()
                Color.line.frame(height: 1)
                if log.items.isEmpty {
                    ContentUnavailableView(
                        "Nothing tracked",
                        systemImage: "clock",
                        description: Text("Add an entry by hand with the + button."),
                    )
                } else {
                    List {
                        Section {
                            ForEach(log.items) { item in
                                Button {
                                    form = .edit(item.entry)
                                } label: {
                                    EntryRow(item: item)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .listRowSeparatorTint(Color.line)
                                .contextMenu {
                                    Button("Edit…") { form = .edit(item.entry) }
                                    Button("Split…") { splitting = item.entry }
                                        .disabled(
                                            EntryEditor.isNoteOnly(item.entry)
                                                || EntryEditor.splitTimes(for: item.entry, calendar: .current) == nil,
                                        )
                                    Button("Delete…", role: .destructive) { deleting = item.entry }
                                        .disabled(EntryEditor.isNoteOnly(item.entry))
                                }
                            }
                        } header: {
                            EntryColumns.header
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationSubtitle(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        } else {
            ContentUnavailableView("The entries could not be read", systemImage: "exclamationmark.triangle")
        }
    }

    private func delete(_ entry: TimeEntry) {
        do {
            try EntryEditor(context: context).delete(entry, at: fixedTime ?? .now)
        } catch let error as EntryChangeError {
            deleteError = error
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "entries")
                .error("Could not delete an entry: \(error.localizedDescription)")
        }
        onChange()
    }
}

/// The day's total and one total per workspace.
private struct DayTotals: View {
    let log: DayLog

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total")
                    .foregroundStyle(Color.muted)
                Text(MenuBarLabel.hoursAndMinutes(log.total))
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            ForEach(log.totals) { total in
                VStack(alignment: .leading, spacing: 2) {
                    WorkspaceName(workspace: total.workspace)
                        .foregroundStyle(Color.muted)
                    Text(MenuBarLabel.hoursAndMinutes(total.tracked))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }
            Spacer()
        }
    }
}

/// One entry's part of the day: time range, workspace, kind, length and note.
private struct EntryRow: View {
    let item: DayLog.Item

    var body: some View {
        HStack(spacing: EntryColumns.spacing) {
            (item.isRunning ? Text("\(timeOfDay(item.start))–now") : Text(verbatim: timeRange(item.start, item.end)))
                .monospacedDigit()
                .frame(width: EntryColumns.time, alignment: .leading)
            Group {
                if let workspace = item.entry.workspace {
                    WorkspaceName(workspace: workspace)
                }
            }
            .frame(width: EntryColumns.workspace, alignment: .leading)
            Text(item.entry.kind.name)
                .foregroundStyle(Color.muted)
                .frame(width: EntryColumns.kind, alignment: .leading)
            Text(MenuBarLabel.hoursAndMinutes(item.length))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(item.counts ? Color.ink : Color.muted)
                .frame(width: EntryColumns.length, alignment: .trailing)
            Text(item.entry.note)
                .lineLimit(1)
                .foregroundStyle(Color.muted)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 30)
    }
}

/// The list's column widths and its header, after the prototype's History table.
private enum EntryColumns {
    static let spacing: CGFloat = 16
    static let time: CGFloat = 130
    static let workspace: CGFloat = 130
    static let kind: CGFloat = 70
    static let length: CGFloat = 50

    static var header: some View {
        HStack(spacing: spacing) {
            Text("Time").frame(width: time, alignment: .leading)
            Text("Workspace").frame(width: workspace, alignment: .leading)
            Text("Kind").frame(width: kind, alignment: .leading)
            Text("Length").frame(width: length, alignment: .trailing)
            Text("Note")
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.muted)
    }
}

/// A workspace's dot and name.
struct WorkspaceName: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(workspace.color.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(workspace.name)
                .lineLimit(1)
        }
    }
}

/// `9:00–10:30` in the user's own format, times of day only. A part
/// clipped at midnight reads `23:30–00:00`.
func timeRange(_ start: Date, _ end: Date) -> String {
    "\(timeOfDay(start))–\(timeOfDay(end))"
}

/// `9:00` in the user's own format.
func timeOfDay(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

extension TimeEntryKind {
    /// The kind's name in the interface.
    var name: LocalizedStringKey {
        switch self {
        case .work: "Work"
        case .break: "Break"
        case .meeting: "Meeting"
        }
    }
}

extension EntryChangeError {
    /// The sentence that tells the user why the change was refused.
    var sentence: String {
        switch self {
        case .noWorkspace:
            return String(localized: "Choose a workspace.")
        case .endNotAfterStart:
            return String(localized: "The end must be after the start.")
        case .inFuture:
            return String(localized: "An entry can't reach into the future.")
        case let .overlaps(start, end):
            // With seconds, since the timer's entries end on any second.
            let range = (start ..< max(start, end)).formatted(.interval.hour().minute().second())
            return String(localized: "It would overlap another entry, \(range).")
        case .runningBlock:
            return String(
                localized: "This entry's block is still running. Only its note can change until the block ends.",
            )
        case .splitNotInside:
            return String(localized: "Choose a time that leaves at least a minute on each side.")
        }
    }
}

#Preview {
    if let container = ModelContainer.sample {
        DayView(
            context: container.mainContext, fixedTime: Date(timeIntervalSince1970: 1_768_466_490),
            historyDay: nil, onChange: {},
        )
        .frame(width: 700, height: 400)
    }
}
