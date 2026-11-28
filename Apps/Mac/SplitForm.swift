import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The sheet that splits an entry in two at a chosen minute. A refused split
/// shows the sentence that says why.
struct SplitForm: View {
    let entry: TimeEntry
    let context: ModelContext
    let fixedTime: Date?
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var refusal: String?
    private let times: ClosedRange<Date>

    init(entry: TimeEntry, context: ModelContext, fixedTime: Date?, onChange: @escaping () -> Void) {
        self.entry = entry
        self.context = context
        self.fixedTime = fixedTime
        self.onChange = onChange
        let end = entry.end ?? entry.start
        // An entry that cannot be split only offers its start, and Split then says why.
        times = EntryEditor.splitTimes(for: entry, calendar: .current) ?? entry.start ... entry.start
        // The middle, so both halves start out about the same.
        let middle = entry.start.addingTimeInterval(end.timeIntervalSince(entry.start) / 2)
        _time = State(initialValue: min(max(middle, times.lowerBound), times.upperBound))
    }

    var body: some View {
        let end = entry.end ?? entry.start
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Entry") {
                        HStack(spacing: 10) {
                            if let workspace = entry.workspace {
                                WorkspaceName(workspace: workspace)
                            }
                            Text(verbatim: timeRange(entry.start, end))
                                .monospacedDigit()
                        }
                    }
                    DatePicker(
                        "Split at",
                        selection: $time,
                        in: times,
                        // With the date when the entry crosses midnight, so the day is clear.
                        displayedComponents: Calendar.current.isDate(entry.start, inSameDayAs: end)
                            ? [.hourAndMinute] : [.date, .hourAndMinute],
                    )
                }
                // What Split makes, so the result is clear before it is pressed.
                Section {
                    LabeledContent("First part") {
                        Text(verbatim: timeRange(entry.start, time)).monospacedDigit()
                    }
                    LabeledContent("Second part") {
                        Text(verbatim: timeRange(time, end)).monospacedDigit()
                    }
                } footer: {
                    Text("Both parts keep the workspace, project, kind and note, and each can then be changed.")
                        .foregroundStyle(Color.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                Button("Split") {
                    split()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        // As wide as the entry form, so the two sheets match.
        .frame(width: 440)
        .navigationTitle("Split entry")
    }

    private func split() {
        do {
            try EntryEditor(context: context).split(entry, at: time, now: fixedTime ?? .now, calendar: .current)
            onChange()
            dismiss()
        } catch let error as EntryChangeError {
            refusal = error.sentence
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "entries")
                .error("Could not split an entry: \(error.localizedDescription)")
            refusal = String(localized: "The entry could not be split.")
        }
    }
}

#Preview {
    let context = ModelContainer.sample?.mainContext
    let entries = try? context?.fetch(FetchDescriptor<TimeEntry>(sortBy: [SortDescriptor(\.start)]))
    if let context, let entry = entries?.first {
        SplitForm(entry: entry, context: context, fixedTime: nil, onChange: {})
    }
}
