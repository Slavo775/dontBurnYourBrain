import Charts
import DontBurnCore
import SwiftData
import SwiftUI

/// A week or a month: a bar chart and the totals per workspace and project,
/// with previous and next.
struct RangeView: View {
    let context: ModelContext
    let fixedTime: Date?
    @Binding var range: HistoryRange
    let open: (RangeTotals.Bar) -> Void

    var body: some View {
        // Every second, so today's bar and the totals count up.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            content(now: fixedTime ?? timeline.date)
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItemGroup {
                Button(range.span == .week ? "Previous week" : "Previous month", systemImage: "chevron.left") {
                    range = range.previous(calendar: .current)
                }
                Button(range.span == .week ? "Next week" : "Next month", systemImage: "chevron.right") {
                    if let next = range.next(now: fixedTime ?? .now, calendar: .current) {
                        range = next
                    }
                }
                .disabled(range.next(now: fixedTime ?? .now, calendar: .current) == nil)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        // A failed read shows a note instead of the chart; the log has the reason.
        if let totals = try? RangeTotals(range, in: context, now: now, calendar: .current) {
            Group {
                if totals.isEmpty {
                    ContentUnavailableView("Nothing tracked", systemImage: "chart.bar")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            RangeChart(totals: totals, open: open)
                                .frame(height: 240)
                            RangeTable(totals: totals)
                        }
                        .padding()
                    }
                }
            }
            .navigationSubtitle(Text(
                "\(Self.name(of: range)), \(MenuBarLabel.hoursAndMinutes(totals.total.tracked)) tracked",
            ))
        } else {
            ContentUnavailableView("The entries could not be read", systemImage: "exclamationmark.triangle")
        }
    }

    /// `12 – 18 Jan 2026` for a week, `January 2026` for a month.
    private static func name(of range: HistoryRange) -> String {
        switch range.span {
        case .week:
            (range.start ..< range.end.addingTimeInterval(-1)).formatted(.interval.day().month().year())
        case .month:
            range.start.formatted(.dateTime.month(.wide).year())
        }
    }
}

/// One bar per day or week, stacked by workspace in the workspace colors. A
/// click on a bar opens it.
private struct RangeChart: View {
    let totals: RangeTotals
    let open: (RangeTotals.Bar) -> Void

    var body: some View {
        let labels = totals.bars.map(label)
        Chart {
            ForEach(totals.bars) { bar in
                ForEach(bar.totals) { total in
                    BarMark(
                        x: .value("Day", label(bar)),
                        y: .value("Hours", total.time.tracked / 3600),
                    )
                    .foregroundStyle(total.workspace.color.color)
                    .accessibilityLabel(spokenName(bar))
                    .accessibilityValue("\(total.workspace.name), \(spoken(total.time.tracked))")
                }
            }
        }
        // Every day or week, empty ones included, so a quiet day never hides.
        .chartXScale(domain: labels)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let bar = bar(named: value.as(String.self)) {
                        VStack(spacing: 2) {
                            Text(verbatim: label(bar))
                            Text(verbatim: MenuBarLabel.hoursAndMinutes(bar.total.tracked))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .chartYAxisLabel("Hours")
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        if let bar = bar(named: proxy.value(atX: location.x - geometry[plot].origin.x)) {
                            open(bar)
                        }
                    }
            }
        }
    }

    /// The bar whose label is `name`.
    private func bar(named name: String?) -> RangeTotals.Bar? {
        totals.bars.first { label($0) == name }
    }

    /// `Mon 12` for a day, `12–18` for the days of a week.
    private func label(_ bar: RangeTotals.Bar) -> String {
        guard totals.range.span == .month else {
            return bar.start.formatted(.dateTime.weekday(.abbreviated).day())
        }
        let last = bar.days.last?.day ?? bar.start
        return last == bar.start
            ? bar.start.formatted(.dateTime.day())
            : (bar.start ..< last).formatted(.interval.day())
    }

    /// The bar's days in full, for VoiceOver.
    private func spokenName(_ bar: RangeTotals.Bar) -> String {
        let last = bar.days.last?.day ?? bar.start
        return last == bar.start
            ? bar.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
            : (bar.start ..< last).formatted(.interval.day().month(.wide))
    }
}

/// The totals per workspace and, below each, per project: work, breaks and
/// their sum. Entries without a project count under the workspace alone.
private struct RangeTable: View {
    let totals: RangeTotals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
            GridRow {
                Text("Workspace")
                Text("Work").gridColumnAlignment(.trailing)
                Text("Breaks").gridColumnAlignment(.trailing)
                Text("Total").gridColumnAlignment(.trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.muted)
            Divider()
            ForEach(totals.totals) { total in
                GridRow {
                    WorkspaceName(workspace: total.workspace)
                    times(total.time)
                }
                .fontWeight(.semibold)
                ForEach(total.projects) { project in
                    GridRow {
                        Text(project.project.name)
                            .padding(.leading, 14)
                        times(project.time)
                    }
                    .foregroundStyle(Color.muted)
                }
            }
            Divider()
            GridRow {
                Text("Total")
                times(totals.total)
            }
            .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func times(_ tally: Tally) -> some View {
        Text(verbatim: MenuBarLabel.hoursAndMinutes(tally.work)).monospacedDigit()
        Text(verbatim: MenuBarLabel.hoursAndMinutes(tally.breaks)).monospacedDigit()
        Text(verbatim: MenuBarLabel.hoursAndMinutes(tally.tracked)).monospacedDigit()
    }
}

/// `2 hours, 30 minutes`, for VoiceOver.
private func spoken(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
}
