import AppKit
import DontBurnCore
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What History shows.
enum HistoryMode: Hashable {
    case day
    case week
    case month
}

/// History: an earlier day, or a week or a month as a chart and totals, with
/// a switch between them and Export….
struct HistoryView: View {
    let context: ModelContext
    let fixedTime: Date?
    let onChange: () -> Void
    /// Opens Today, for a click on today's bar.
    let openToday: () -> Void

    @State private var mode: HistoryMode
    @State private var day: Date
    @State private var range: HistoryRange
    @State private var exportFailed = false

    /// History on yesterday, or with `mode` on the current week or month.
    init(
        context: ModelContext, fixedTime: Date?, mode: HistoryMode = .day,
        onChange: @escaping () -> Void, openToday: @escaping () -> Void,
    ) {
        self.context = context
        self.fixedTime = fixedTime
        self.onChange = onChange
        self.openToday = openToday
        let now = fixedTime ?? .now
        _mode = State(initialValue: mode)
        _day = State(initialValue: DayLog.day(before: now, calendar: .current))
        _range = State(initialValue: HistoryRange(mode == .month ? .month : .week, containing: now, calendar: .current))
    }

    var body: some View {
        Group {
            switch mode {
            case .day:
                DayView(context: context, fixedTime: fixedTime, historyDay: $day, onChange: onChange)
            case .week, .month:
                RangeView(context: context, fixedTime: fixedTime, range: $range, open: open)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: modeChoice) {
                    Text("Day").tag(HistoryMode.day)
                    Text("Week").tag(HistoryMode.week)
                    Text("Month").tag(HistoryMode.month)
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button("Export…", systemImage: "square.and.arrow.up") {
                    export()
                }
            }
        }
        .alert("The file could not be saved", isPresented: $exportFailed) {
            Button("OK") {}
        }
    }

    /// The mode, where a week or a month opens on the current one.
    private var modeChoice: Binding<HistoryMode> {
        Binding(get: { mode }, set: { choice in
            switch choice {
            case .day: break
            case .week: range = HistoryRange(.week, containing: fixedTime ?? .now, calendar: .current)
            case .month: range = HistoryRange(.month, containing: fixedTime ?? .now, calendar: .current)
            }
            mode = choice
        })
    }

    /// Opens a bar: a week's day in Day, today in Today, a month's week in Week.
    private func open(_ bar: RangeTotals.Bar) {
        let calendar = Calendar.current
        let now = fixedTime ?? .now
        switch range.span {
        case .week:
            if calendar.isDate(bar.start, inSameDayAs: now) {
                openToday()
            } else if bar.start < now {
                day = bar.start
                mode = .day
            }
        case .month:
            range = HistoryRange(.week, containing: bar.start, calendar: calendar)
            mode = .week
        }
    }

    /// Asks where to save the shown range's entries as CSV, then writes them there once.
    private func export() {
        let calendar = Calendar.current
        let interval = mode == .day
            ? calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86400)
            : DateInterval(start: range.start, end: range.end)
        let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "export")
        let text: String
        do {
            let entries = try EntryExport.entries(startingIn: interval, in: context, now: fixedTime ?? .now)
            text = EntryExport.csv(entries, timeZone: calendar.timeZone)
        } catch {
            log.error("Could not read the entries to export: \(error.localizedDescription)")
            exportFailed = true
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = Self.fileName(for: interval, calendar: calendar)
        panel.directoryURL = Self.exportFolder
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("Could not write the export: \(error.localizedDescription)")
                exportFailed = true
            }
        }
    }

    /// `2026-01-12–2026-01-18.csv`, or `2026-01-14.csv` for one day.
    private static func fileName(for interval: DateInterval, calendar: Calendar) -> String {
        let format = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        let first = interval.start.formatted(format)
        let last = interval.end.addingTimeInterval(-1).formatted(format)
        return first == last ? "\(first).csv" : "\(first)–\(last).csv"
    }

    /// The folder the save panel opens in with `-DontBurnExportFolder <path>`,
    /// for checks that keep their files in a temporary folder, or `nil` for
    /// the panel's own choice. Only an absolute path to an existing folder.
    private static var exportFolder: URL? {
        guard let raw = DontBurnApp.launchArgument("DontBurnExportFolder"),
              raw.utf8.count <= 1024, raw.hasPrefix("/")
        else { return nil }
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: raw, isDirectory: &isFolder)
        return exists && isFolder.boolValue ? URL(filePath: raw, directoryHint: .isDirectory) : nil
    }
}

#Preview("Week") {
    if let container = ModelContainer.sample {
        HistoryView(
            context: container.mainContext, fixedTime: Date(timeIntervalSince1970: 1_768_466_490), mode: .week,
            onChange: {}, openToday: {},
        )
        .frame(width: 700, height: 600)
    }
}

#Preview("Month") {
    if let container = ModelContainer.sample {
        HistoryView(
            context: container.mainContext, fixedTime: Date(timeIntervalSince1970: 1_768_466_490), mode: .month,
            onChange: {}, openToday: {},
        )
        .frame(width: 700, height: 600)
    }
}
