import Charts
import PracticeKit
import SwiftUI

/// Single series → one hue, no legend; goal as a dashed rule; tap for values.
struct DailyMinutesChart: View {
    let buckets: [DayTotal]
    let unit: Calendar.Component
    let goalMinutes: Int?
    @State private var selected: Date?

    private var selectedBucket: DayTotal? {
        guard let selected else { return nil }
        let calendar = Calendar.current
        return buckets.first { calendar.isDate($0.day, equalTo: selected, toGranularity: unit) }
    }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value("Date", bucket.day, unit: unit), y: .value("Minutes", bucket.minutes))
                    .foregroundStyle(Color(hex: "#2A78D6"))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .opacity(selectedBucket == nil || selectedBucket?.day == bucket.day ? 1 : 0.4)
            }
            if let goalMinutes {
                RuleMark(y: .value("Goal", goalMinutes))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let bucket = selectedBucket {
                RuleMark(x: .value("Selected", bucket.day, unit: unit))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 2) {
                            Text(bucket.day, format: unit == .day ? .dateTime.weekday().month().day() : .dateTime.month().year())
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(DurationText.short(bucket.seconds)).font(.caption.bold())
                        }
                        .padding(6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks(position: .leading) { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .chartYAxisLabel("min")
        .frame(height: 200)
        .accessibilityChartDescriptor(BarChartDescriptor(
            title: String(localized: "Minutes practiced"),
            points: buckets.map { ($0.day.formatted(unit == .day ? .dateTime.month().day() : .dateTime.month().year()), $0.minutes) },
            unit: String(localized: "minutes")))
    }
}

/// Stacked bars; color follows the instrument (its own swatch), with a legend
/// and a surface gap between segments.
struct InstrumentStackChart: View {
    let totals: [InstrumentDayTotal]
    let unit: Calendar.Component
    let instruments: [Instrument]
    @Environment(\.colorScheme) private var colorScheme

    private var series: [(name: String, color: Color)] {
        let ids = Set(totals.map(\.instrumentID))
        var result = instruments.filter { ids.contains($0.id) }.map {
            ($0.name, Color(hex: InstrumentPalette.hex($0.colorHex, dark: colorScheme == .dark)))
        }
        if ids.contains(nil) { result.append((String(localized: "No instrument"), Color.gray)) }
        return result
    }

    private func name(_ id: UUID?) -> String {
        instruments.first { $0.id == id }?.name ?? String(localized: "No instrument")
    }

    var body: some View {
        let series = self.series
        Chart(totals) { total in
            BarMark(x: .value("Date", total.bucket, unit: unit), y: .value("Minutes", total.seconds / 60))
                .foregroundStyle(by: .value("Instrument", name(total.instrumentID)))
        }
        .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxisLabel("min")
        .frame(height: 200)
    }
}

/// Ranked magnitudes: horizontal bars, one hue, label + value as text.
struct HorizontalBars: View {
    let rows: [(String, Double)]
    let title: String

    var body: some View {
        Chart(Array(rows.enumerated()), id: \.offset) { _, row in
            BarMark(x: .value("Minutes", row.1), y: .value("Item", row.0))
                .foregroundStyle(Color(hex: "#2A78D6"))
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                .annotation(position: .trailing, alignment: .leading) {
                    Text(DurationText.short(row.1 * 60)).font(.caption).foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks { AxisValueLabel().font(.caption) } }
        .frame(height: CGFloat(max(1, rows.count)) * 34 + 10)
        .accessibilityChartDescriptor(BarChartDescriptor(title: title, points: rows, unit: String(localized: "minutes")))
    }
}

/// GitHub-style grid of practice days, sequential single-hue ramp.
struct PracticeHeatmap: View {
    let totals: [Date: TimeInterval]
    let weeks: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let maxSeconds = max(totals.values.max() ?? 1, 60)
        let practicedDays = totals.values.filter { $0 > 0 }.count
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<7, id: \.self) { weekday in
                GridRow {
                    ForEach(0..<weeks, id: \.self) { week in
                        let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(for: totals[calendar.startOfDay(for: day)] ?? 0, max: maxSeconds, future: day > Date()))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practice days")
        .accessibilityValue("Practiced on \(practicedDays) days in the last \(weeks) weeks")
    }

    private func color(for seconds: TimeInterval, max: TimeInterval, future: Bool) -> Color {
        if future { return .clear }
        guard seconds > 0 else { return Color.secondary.opacity(0.12) }
        let ramp = InstrumentPalette.sequentialBlue
        let steps = colorScheme == .dark ? Array(ramp.reversed()) : ramp
        // Skip the lightest step so any practice is visible against the surface.
        let index = 1 + Int((seconds / max) * Double(steps.count - 2)).clamped(0, steps.count - 2)
        return Color(hex: steps[index])
    }
}

/// Two measures on the same 1–5 scale: one axis, legend, distinct symbols.
struct RatingFocusChart: View {
    let averages: [WeeklyAverage]

    var body: some View {
        Chart {
            ForEach(averages) { week in
                if let rating = week.rating {
                    LineMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("Average", rating),
                             series: .value("Measure", String(localized: "Rating")))
                        .foregroundStyle(by: .value("Measure", String(localized: "Rating")))
                        .symbol(by: .value("Measure", String(localized: "Rating")))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let focus = week.focus {
                    LineMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("Average", focus),
                             series: .value("Measure", String(localized: "Focus")))
                        .foregroundStyle(by: .value("Measure", String(localized: "Focus")))
                        .symbol(by: .value("Measure", String(localized: "Focus")))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartForegroundStyleScale([String(localized: "Rating"): Color(hex: "#2A78D6"), String(localized: "Focus"): Color(hex: "#EB6834")])
        .chartYScale(domain: 1...5)
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 180)
    }
}

extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}
