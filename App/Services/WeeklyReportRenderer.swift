import Charts
import PracticeKit
import SwiftData
import SwiftUI

/// Renders a one-page weekly report (minutes per day, per item, notes) as PDF.
@MainActor
enum WeeklyReportRenderer {
    static func renderPDF(context: ModelContext, goal: GoalSettings, to url: URL, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
        let start = week.start, end = week.end
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let records = sessions.map(SessionRecord.init)
        let items = (try? context.fetch(FetchDescriptor<PracticeItem>())) ?? []
        let stats = StatsCalculator(calendar: calendar)
        let report = WeeklyReportView(
            week: week,
            total: stats.total(records),
            days: stats.bucketTotals(records, in: week),
            items: stats.topItems(records, limit: 12).map { entry in
                (items.first { $0.id == entry.key }?.title ?? String(localized: "Deleted item"), entry.seconds)
            },
            notes: sessions.filter { !$0.notes.isEmpty }.map { ($0.startDate, $0.notes) },
            goalMinutes: goal.dailyMinutes)

        let renderer = ImageRenderer(content: report.frame(width: 612).environment(\.colorScheme, .light))
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: CGSize(width: 612, height: max(792, size.height)))
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok
    }
}

private struct WeeklyReportView: View {
    let week: DateInterval
    let total: TimeInterval
    let days: [DayTotal]
    let items: [(String, TimeInterval)]
    let notes: [(Date, String)]
    let goalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice report").font(.largeTitle.bold())
                Text("\(week.start, format: .dateTime.month().day()) – \(week.end.addingTimeInterval(-1), format: .dateTime.month().day().year())")
                    .foregroundStyle(.secondary)
                Text("Total: \(DurationText.spoken(total)) on \(days.filter { $0.seconds > 0 }.count) days")
                    .font(.headline)
            }
            Chart(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.minutes))
                    .foregroundStyle(Color(hex: "#2A78D6"))
                RuleMark(y: .value("Goal", goalMinutes)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.gray)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
            .frame(height: 180)

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time per item").font(.headline)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack { Text(item.0); Spacer(); Text(DurationText.short(item.1)).monospacedDigit() }
                        Divider()
                    }
                }
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").font(.headline)
                    ForEach(Array(notes.prefix(10).enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.0, format: .dateTime.weekday(.wide)).font(.caption.bold()).foregroundStyle(.secondary)
                            Text(note.1).font(.callout)
                        }
                    }
                }
            }
            Text("Made with Ostinato").font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.white)
    }
}
