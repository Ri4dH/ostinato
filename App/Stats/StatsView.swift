import Charts
import PracticeKit
import SwiftData
import SwiftUI

/// Everything the Stats tab shows for one range, computed once per load.
struct StatsData {
    var total: TimeInterval = 0
    var buckets: [DayTotal] = []
    var bucket: Calendar.Component = .day
    var byInstrument: [InstrumentDayTotal] = []
    var topItems: [KeyedTotal<UUID>] = []
    var categories: [KeyedTotal<ItemCategory>] = []
    var streak = StreakInfo(current: 0, longest: 0, isPendingToday: false)
    var goal = GoalCompletion(daysMet: 0, daysElapsed: 0, weeksMet: 0, weeksElapsed: 0)
    var averages: [WeeklyAverage] = []
    var heatmap: [Date: TimeInterval] = [:]
}

struct StatsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Instrument.sortIndex) private var instruments: [Instrument]
    @Query private var items: [PracticeItem]

    @State private var range: StatsRange = .week
    @State private var data = StatsData()
    @State private var records: [SessionRecord] = []
    @State private var showAsList = false
    @State private var summary: WeeklySummary?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if records.isEmpty {
                        EmptyStateView(title: "No stats yet", message: "Practice a few sessions to see trends here.",
                                       systemImage: "chart.bar")
                            .frame(minHeight: 320)
                    } else {
                        StatTiles(data: data, goal: settings.goal)
                        if let summary, range == .week { WeeklySummaryCard(summary: summary) }
                        if showAsList {
                            StatsListView(data: data, itemTitle: itemTitle, instrumentName: instrumentName)
                        } else {
                            charts
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showAsList) { Label("Show as List", systemImage: "list.bullet") }
                        .toggleStyle(.button)
                }
            }
            .task(id: model.statsStore.revision) { await load() }
            .onChange(of: range) { recompute() }
        }
    }

    @ViewBuilder private var charts: some View {
        ChartCard(title: range.bucket == .day ? "Minutes per day" : "Minutes per month") {
            DailyMinutesChart(buckets: data.buckets, unit: data.bucket,
                              goalMinutes: range.bucket == .day ? settings.goal.dailyMinutes : nil)
        }
        if Set(data.byInstrument.map(\.instrumentID)).count > 1 {
            ChartCard(title: "By instrument") {
                InstrumentStackChart(totals: data.byInstrument, unit: data.bucket, instruments: instruments)
            }
        }
        if !data.topItems.isEmpty {
            ChartCard(title: "Top items") {
                HorizontalBars(rows: data.topItems.map { (itemTitle($0.key), $0.minutes) }, title: "Top items")
            }
        }
        if !data.categories.isEmpty {
            ChartCard(title: "By category") {
                HorizontalBars(rows: data.categories.map { ($0.key.displayName, $0.minutes) }, title: "By category")
            }
        }
        ChartCard(title: "Practice days", subtitle: "Last 26 weeks") {
            PracticeHeatmap(totals: data.heatmap, weeks: 26)
        }
        if data.averages.contains(where: { $0.rating != nil || $0.focus != nil }) {
            ChartCard(title: "Rating and focus", subtitle: "Weekly average, 1–5") {
                RatingFocusChart(averages: data.averages)
            }
        }
    }

    private func itemTitle(_ id: UUID) -> String {
        items.first { $0.id == id }?.title ?? String(localized: "Deleted item")
    }

    private func instrumentName(_ id: UUID?) -> String {
        instruments.first { $0.id == id }?.name ?? String(localized: "No instrument")
    }

    private func load() async {
        records = model.statsStore.records
        recompute()
        let titles = Dictionary(items.map { ($0.id, (title: $0.title, category: $0.category)) }, uniquingKeysWith: { a, _ in a })
        // Notes only for this week: a small, predicate-limited fetch.
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) ?? DateInterval()
        let start = week.start, end = week.end
        let notes = ((try? context.fetch(FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end }))) ?? [])
            .map(\.notes).filter { !$0.isEmpty }
        let input = WeeklySummaryInput.make(records: model.statsStore.records, itemTitles: titles, notes: notes,
                                            goal: settings.goal, now: Date(), calendar: .current)
        // Show the instant rules-based summary, then upgrade if the on-device
        // model produces one (that can take several seconds).
        summary = RulesBasedSummary.make(input)
        guard WeeklySummaryGenerator.isModelAvailable, input.totalMinutes > 0 else { return }
        let generated = await WeeklySummaryGenerator.summary(for: input)
        // A newer load may have started while this one awaited.
        guard !Task.isCancelled, generated.isGenerated else { return }
        summary = generated
    }

    private func recompute() {
        let calendar = Calendar.current
        let stats = StatsCalculator(calendar: calendar)
        let now = Date()
        let interval = range.interval(containing: now, calendar: calendar, earliest: records.map(\.startDate).min())
        let inRange = records.filter { interval.contains($0.startDate) }
        let heatStart = calendar.date(byAdding: .weekOfYear, value: -26, to: now) ?? now
        data = StatsData(
            total: stats.total(inRange),
            buckets: stats.bucketTotals(records, in: interval, bucket: range.bucket),
            bucket: range.bucket,
            byInstrument: stats.instrumentBucketTotals(records, in: interval, bucket: range.bucket),
            topItems: stats.topItems(inRange, limit: 10),
            categories: stats.totalsByCategory(inRange),
            streak: stats.streak(records, goal: settings.goal, now: now),
            goal: stats.goalCompletion(records, goal: settings.goal, in: interval, now: now),
            averages: stats.weeklyAverages(records, in: range == .week
                ? DateInterval(start: calendar.date(byAdding: .weekOfYear, value: -11, to: interval.start) ?? interval.start, end: interval.end)
                : interval),
            heatmap: stats.dayTotals(records.filter { $0.startDate >= heatStart }))
    }
}

/// Headline numbers are tiles, not charts.
struct StatTiles: View {
    let data: StatsData
    let goal: GoalSettings
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // One column at accessibility sizes so numbers never clip.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(GridLayout(horizontalSpacing: 12, verticalSpacing: 12))
        layout {
            GridRow {
                tile("Total", DurationText.short(data.total), DurationText.spoken(data.total))
                tile("Streak", String(localized: "\(data.streak.current) days"),
                     String(localized: "Current streak \(data.streak.current) days, longest \(data.streak.longest) days"),
                     detail: String(localized: "Longest \(data.streak.longest)"))
            }
            GridRow {
                tile("Weekly goal", data.goal.weeksElapsed == 0 ? "–" : data.goal.weeklyRate.formatted(.percent.precision(.fractionLength(0))),
                     String(localized: "\(data.goal.weeksMet) of \(data.goal.weeksElapsed) weeks met \(goal.daysPerWeek) practice days"),
                     detail: String(localized: "\(data.goal.weeksMet) of \(data.goal.weeksElapsed) weeks"))
                tile("Daily goal", "\(data.goal.daysMet)",
                     String(localized: "\(data.goal.daysMet) days reached \(goal.dailyMinutes) minutes"),
                     detail: String(localized: "days ≥ \(goal.dailyMinutes) min"))
            }
        }
    }

    private func tile(_ title: LocalizedStringKey, _ value: String, _ spoken: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title.bold()).monospacedDigit().lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(spoken)
    }
}

struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
    }
}

/// On-device weekly summary (rules-based fallback when Apple Intelligence is off).
struct WeeklySummaryCard: View {
    let summary: WeeklySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(summary.isGenerated ? "Summary · generated on device" : "This week",
                  systemImage: summary.isGenerated ? "apple.intelligence" : "text.alignleft")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary.headline).font(.headline)
            ForEach(summary.observations, id: \.self) { Text("• \($0)").font(.subheadline) }
            Text(summary.suggestion).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.quinary, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

/// The same numbers as plain rows, for anyone who prefers text.
struct StatsListView: View {
    let data: StatsData
    let itemTitle: (UUID) -> String
    let instrumentName: (UUID?) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("Per \(data.bucket == .day ? "day" : "month")", data.buckets.filter { $0.seconds > 0 }.map {
                ($0.day.formatted(data.bucket == .day ? .dateTime.weekday().month().day() : .dateTime.month().year()), $0.seconds)
            })
            group("Top items", data.topItems.map { (itemTitle($0.key), $0.seconds) })
            group("By category", data.categories.map { ($0.key.displayName, $0.seconds) })
            let byInstrument = Dictionary(grouping: data.byInstrument, by: \.instrumentID)
                .map { (instrumentName($0.key), $0.value.reduce(0) { $0 + $1.seconds }) }
                .sorted { $0.1 > $1.1 }
            group("By instrument", byInstrument)
        }
    }

    private func group(_ title: String, _ rows: [(String, TimeInterval)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if rows.isEmpty { Text("Nothing in this range").foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                    Spacer()
                    Text(DurationText.short(row.1)).monospacedDigit().foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Divider()
            }
        }
    }
}
