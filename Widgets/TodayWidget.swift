import AppIntents
import PracticeKit
import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let active: ActiveSession?

    var minutes: Int { snapshot.todayMinutes(now: date, calendar: .current, active: active) }
    var progress: Double { snapshot.goalProgress(now: date, calendar: .current, active: active) }
}

/// Reads the small JSON files the app writes to the App Group.
struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder, active: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let entry = load(at: now)
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        // While practicing, step every few minutes so the ring fills; otherwise reset at midnight.
        if entry.active != nil {
            let entries = (0..<12).map { load(at: now.addingTimeInterval(Double($0) * 300)) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
        } else {
            completion(Timeline(entries: [entry, load(at: midnight)], policy: .after(midnight)))
        }
    }

    private func load(at date: Date) -> TodayEntry {
        let dir = AppIdentifiers.current.sharedDirectory
        let snapshot = WidgetSnapshotStore(directory: dir).load() ?? WidgetSnapshot(
            todaySeconds: 0, todayDate: date, goalMinutes: GoalSettings.default.dailyMinutes, streak: 0,
            week: [], lastInstrument: nil, updatedAt: date)
        return TodayEntry(date: date, snapshot: snapshot, active: FileActiveSessionStore(directory: dir).load())
    }
}

/// Home Screen: small (ring) and medium (ring + streak + week bars).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ostinato.today", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Minutes practiced today and your streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 8) {
                    if entry.snapshot.streak > 0 {
                        Label("\(entry.snapshot.streak)-day streak", systemImage: "flame.fill")
                            .font(.caption.bold()).foregroundStyle(.orange)
                    }
                    WeekBars(days: entry.snapshot.week, goal: entry.snapshot.goalMinutes)
                    startButton
                }
            }
        default:
            VStack(spacing: 8) {
                ring
                startButton
            }
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.tint.opacity(0.2), lineWidth: 8)
            Circle().trim(from: 0, to: entry.progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(entry.progress > 0 ? 1 : 0)
            VStack(spacing: 0) {
                Text("\(entry.minutes)").font(.title2.bold()).monospacedDigit()
                Text("of \(entry.snapshot.goalMinutes) min").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today: \(entry.minutes) of \(entry.snapshot.goalMinutes) minutes")
    }

    @ViewBuilder private var startButton: some View {
        if let active = entry.active {
            Text(active.isPaused ? "Paused" : "Practicing")
                .font(.caption.bold())
                .foregroundStyle(.tint)
        } else {
            Button(intent: StartPracticeIntent()) {
                Label("Start", systemImage: "play.fill").font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

struct WeekBars: View {
    let days: [WidgetSnapshot.Day]
    let goal: Int

    var body: some View {
        let maxMinutes = max(goal, days.map(\.minutes).max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.minutes >= goal ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.45)))
                        .frame(width: 10, height: max(2, 36 * CGFloat(day.minutes) / CGFloat(maxMinutes)))
                    Text(day.date, format: .dateTime.weekday(.narrow)).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("This week: \(days.reduce(0) { $0 + $1.minutes }) minutes")
    }
}

/// Lock Screen: circular ring, inline "24 min today · 🔥 12", rectangular.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ostinato.lockscreen", provider: TodayProvider()) { entry in
            LockScreenView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Practice")
        .description("Today's minutes at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

struct LockScreenView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            if entry.snapshot.streak > 0 {
                Text("\(entry.minutes) min today · 🔥 \(entry.snapshot.streak)")
            } else {
                Text("\(entry.minutes) min today")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Practice").font(.headline).widgetAccentable()
                Text("\(entry.minutes) of \(entry.snapshot.goalMinutes) min")
                if entry.snapshot.streak > 0 { Text("🔥 \(entry.snapshot.streak)-day streak").font(.caption) }
            }
        default:
            Gauge(value: entry.progress) {
                Image(systemName: "music.note")
            } currentValueLabel: {
                Text("\(entry.minutes)")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}
