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
                    // The prototype's main area: 24 pt above, 28 pt at the sides, 26 pt between.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            RangeChart(totals: totals, now: now, open: open)
                                .frame(height: 250)
                            RangeTable(totals: totals)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
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

/// One bar per day or week, stacked by workspace in the workspace colors,
/// with its total above it, as the prototype draws History. A click on a bar,
/// or VoiceOver's press, opens it.
private struct RangeChart: View {
    let totals: RangeTotals
    let now: Date
    let open: (RangeTotals.Bar) -> Void

    /// The bar's share of its column, about the prototype's 52 pt in a week.
    private static let width = MarkDimension.ratio(0.55)

    var body: some View {
        Chart {
            ForEach(totals.bars) { bar in
                let name = label(bar)
                let shown = bar.totals.filter { $0.time.tracked > 0 }
                ForEach(shown) { total in
                    let corner: CGFloat = total.id == shown.last?.id ? 6 : 0
                    BarMark(x: .value("Day", name), y: .value("Hours", total.time.tracked / 3600), width: Self.width)
                        .foregroundStyle(total.workspace.color.color)
                        // A 2 pt gap above each part but the top one, whose corners are rounded.
                        .offset(yEnd: corner > 0 ? 0 : 2)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner))
                        .accessibilityHidden(true)
                }
            }
        }
        // Every day or week, empty ones included, so a quiet day never hides.
        .chartXScale(domain: totals.bars.map(label))
        .chartYScale(domain: 0 ... top)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let name = value.as(String.self) {
                        Text(verbatim: name)
                    }
                }
                .font(.callout)
                .foregroundStyle(Color.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top / 2, top]) { value in
                let hours = value.as(Double.self) ?? 0
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: hours == 0 ? [] : [3, 3]))
                    .foregroundStyle(Color.line)
                AxisValueLabel {
                    if hours == 0 {
                        Text(verbatim: "0")
                    } else {
                        Text("\(Int(hours)) h")
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.muted)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let frame = proxy.plotFrame {
                    let plot = geometry[frame]
                    let column = plot.width / CGFloat(max(totals.bars.count, 1))
                    ForEach(totals.bars) { bar in
                        let height = bar.total.tracked / 3600
                        if let center = proxy.position(forX: label(bar)), let barTop = proxy.position(forY: height) {
                            // The total 6 pt above the bar. The bar's button reads it to VoiceOver.
                            Text(verbatim: MenuBarLabel.hoursAndMinutes(bar.total.tracked))
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(bar.total.tracked > 0 ? Color.ink : Color.muted)
                                .fixedSize()
                                .position(x: plot.minX + center, y: plot.minY + barTop - 14)
                                .accessibilityHidden(true)
                            BarButton(bar: bar, span: totals.range.span, name: spokenName(bar)) {
                                open(bar)
                            }
                            // A day or week still to come has nothing to open.
                            .disabled(bar.start > now)
                            .frame(width: column, height: plot.height)
                            .position(x: plot.minX + center, y: plot.midY)
                        }
                    }
                }
            }
        }
    }

    /// The top of the hours axis: the first round number at or above the
    /// tallest bar, so the axis reads 0, half of it and all of it.
    private var top: Double {
        let tallest = (totals.bars.map(\.total.tracked).max() ?? 0) / 3600
        return [2, 4, 6, 8, 10, 12, 16, 20, 24, 30, 40, 50, 60, 80, 100, 120, 160, 200].first { $0 >= tallest } ?? 200
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

/// The clear button over one bar's column. A click opens the bar, and
/// VoiceOver reads the bar as one element with its time per workspace.
private struct BarButton: View {
    let bar: RangeTotals.Bar
    let span: HistoryRange.Span
    /// The bar's days in full.
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .help(span == .week ? Text("Open this day") : Text("Open this week"))
        .accessibilityLabel(label)
    }

    /// `Monday 12 January. Acme, 3 hours. Globex, 2 hours, 30 minutes. In all, 5 hours, 30 minutes.`
    /// One sentence per workspace, because a spoken time holds commas itself.
    private var label: Text {
        let parts = bar.totals.filter { $0.time.tracked > 0 }
            .map { String(localized: "\($0.workspace.name), \(spokenTime($0.time.tracked)).") }
        guard !parts.isEmpty else { return Text("\(name). Nothing tracked.") }
        return Text("\(name). \(parts.joined(separator: " ")) In all, \(spokenTime(bar.total.tracked)).")
    }
}

/// The totals per workspace and, below each, per project: work, breaks and
/// their sum. Entries without a project count under the workspace alone. The
/// table names every number the chart shows in color.
private struct RangeTable: View {
    let totals: RangeTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TallyRow {
                Text("Workspace")
            } numbers: {
                Text("Work")
                Text("Breaks")
                Text("Total")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.muted)
            .frame(minHeight: 22, alignment: .top)
            // Each row names its columns for VoiceOver.
            .accessibilityHidden(true)
            ForEach(totals.totals) { total in
                Color.line.frame(height: 1)
                TallyLine(time: total.time, name: total.workspace.name) {
                    WorkspaceName(workspace: total.workspace)
                }
                .fontWeight(.semibold)
                .frame(minHeight: 34)
                ForEach(total.projects) { project in
                    TallyLine(time: project.time, name: project.project.name) {
                        // Under the workspace's name, past its dot.
                        Text(project.project.name)
                            .lineLimit(1)
                            .padding(.leading, 14)
                    }
                    .frame(minHeight: 26)
                }
                Spacer().frame(height: 4)
            }
            Color.line.frame(height: 1)
            TallyLine(time: totals.total, name: String(localized: "Total")) {
                Text("Total")
            }
            .fontWeight(.semibold)
            .frame(minHeight: 34)
        }
    }
}

/// One row of the table: a name, then work, breaks and total in tabular figures.
private struct TallyLine<Name: View>: View {
    let time: Tally
    /// The name VoiceOver reads first.
    let name: String
    @ViewBuilder let label: Name

    var body: some View {
        TallyRow {
            label
        } numbers: {
            number(time.work)
            number(time.breaks)
            number(time.tracked)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(spokenLabel)
    }

    /// `Acme. Work, 3 hours. Breaks, 15 minutes. Total, 3 hours, 15 minutes.`
    private var spokenLabel: Text {
        let (work, breaks, total) = (spokenTime(time.work), spokenTime(time.breaks), spokenTime(time.tracked))
        return Text("\(name). Work, \(work). Breaks, \(breaks). Total, \(total).")
    }

    /// `1:30`, muted when it is nothing.
    private func number(_ seconds: TimeInterval) -> some View {
        Text(verbatim: MenuBarLabel.hoursAndMinutes(seconds))
            .monospacedDigit()
            .foregroundStyle(seconds > 0 ? Color.ink : Color.muted)
    }
}

/// The table's columns: the name fills the width, and the three numbers stand
/// right-aligned at the end, as the prototype's Time column does.
private struct TallyRow<Name: View, Numbers: View>: View {
    @ViewBuilder let name: Name
    @ViewBuilder let numbers: Numbers

    var body: some View {
        HStack(spacing: 16) {
            name
                .frame(maxWidth: .infinity, alignment: .leading)
            Group(subviews: numbers) { columns in
                ForEach(columns) { column in
                    column.frame(width: 64, alignment: .trailing)
                }
            }
        }
    }
}

/// `2 hours, 30 minutes`, for VoiceOver.
func spokenTime(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .wide))
}
