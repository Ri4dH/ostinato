import Charts
import PracticeKit
import SwiftData
import SwiftUI

/// Renders a shareable practice report for a teacher: minutes per day, time
/// and tempo progress per item, time per category, and notes.
@MainActor
enum PracticeReportRenderer {
    static func renderPDF(context: ModelContext, goal: GoalSettings, period: ReportPeriod, to url: URL,
                          now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let interval = period.interval(now: now, calendar: calendar)
        let start = interval.start, end = interval.end
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
            sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let records = sessions.map(SessionRecord.init)
        let items = (try? context.fetch(FetchDescriptor<PracticeItem>())) ?? []
        let stats = StatsCalculator(calendar: calendar)
        let report = PracticeReportView(
            title: period.displayName,
            interval: interval,
            total: stats.total(records),
            days: stats.bucketTotals(records, in: interval),
            items: stats.topItems(records, limit: 15).map { entry in
                let item = items.first { $0.id == entry.key }
                return ReportItemRow(title: item?.title ?? String(localized: "Deleted item"),
                                     composer: item?.composer, seconds: entry.seconds,
                                     tempo: item?.lastTempo, target: item?.targetTempo)
            },
            categories: stats.totalsByCategory(records).map { ($0.key.displayName, $0.seconds) },
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

struct ReportItemRow {
    var title: String
    var composer: String?
    var seconds: TimeInterval
    var tempo: Int?
    var target: Int?
}

private struct PracticeReportView: View {
    let title: String
    let interval: DateInterval
    let total: TimeInterval
    let days: [DayTotal]
    let items: [ReportItemRow]
    let categories: [(String, TimeInterval)]
    let notes: [(Date, String)]
    let goalMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Practice report · \(title)").font(.largeTitle.bold())
                Text("\(interval.start, format: .dateTime.month().day()) – \(interval.end.addingTimeInterval(-1), format: .dateTime.month().day().year())")
                    .foregroundStyle(.secondary)
                Text("Total: \(DurationText.spoken(total)) on \(days.filter { $0.seconds > 0 }.count) days")
                    .font(.headline)
            }
            Chart(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Minutes", day.minutes))
                    .foregroundStyle(Color(hex: "#2A78D6"))
                RuleMark(y: .value("Goal", goalMinutes)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.gray)
            }
            .chartXAxis {
                if days.count <= 7 {
                    AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)) }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.month().day()) }
                }
            }
            .chartYAxisLabel("min")
            .frame(height: 180)

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Time per item").font(.headline)
                        Spacer()
                        Text("Tempo").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                        Text("Time").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 100, alignment: .trailing)
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title)
                                if let composer = item.composer { Text(composer).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(tempoText(item)).monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(DurationText.short(item.seconds)).monospacedDigit().lineLimit(1).frame(width: 100, alignment: .trailing)
                        }
                        Divider()
                    }
                }
            }
            if !categories.isEmpty {
                Text(categories.map { "\($0.0) \(DurationText.short($0.1))" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").font(.headline)
                    ForEach(Array(notes.suffix(15).enumerated()), id: \.offset) { _, note in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.0, format: .dateTime.weekday(.wide).month().day()).font(.caption.bold()).foregroundStyle(.secondary)
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

    private func tempoText(_ item: ReportItemRow) -> String {
        switch (item.tempo, item.target) {
        case let (tempo?, target?): "\(tempo) / \(target)"
        case let (tempo?, nil): "\(tempo)"
        case let (nil, target?): "– / \(target)"
        default: ""
        }
    }
}
