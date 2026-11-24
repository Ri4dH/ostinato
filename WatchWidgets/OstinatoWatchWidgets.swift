import PracticeKit
import SwiftUI
import WidgetKit

@main
struct OstinatoWatchWidgets: WidgetBundle {
    var body: some Widget { PracticeComplication() }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let minutes: Int
    let goal: Int
    let streak: Int
    let isPracticing: Bool
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: .now, minutes: 24, goal: 30, streak: 12, isPracticing: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load(.now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let entries = (0..<8).map { load(now.addingTimeInterval(Double($0) * 900)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(7200))))
    }

    private func load(_ date: Date) -> ComplicationEntry {
        let dir = AppIdentifiers.current.sharedDirectory
        let snapshot = WidgetSnapshotStore(directory: dir).load()
        let active = FileActiveSessionStore(directory: dir).load()
        return ComplicationEntry(
            date: date,
            minutes: snapshot?.todayMinutes(now: date, calendar: .current, active: active) ?? 0,
            goal: snapshot?.goalMinutes ?? GoalSettings.default.dailyMinutes,
            streak: snapshot?.streak ?? 0,
            isPracticing: active != nil)
    }
}

/// Today's minutes vs goal and streak; tap opens the app to start.
struct PracticeComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ostinato.watch.today", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Practice")
        .description("Today's minutes and streak.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    private var progress: Double { entry.goal > 0 ? min(1, Double(entry.minutes) / Double(entry.goal)) : 0 }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.streak > 0 ? "\(entry.minutes) min · 🔥 \(entry.streak)" : "\(entry.minutes) min today")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text(entry.isPracticing ? "Practicing" : "Practice").font(.headline).widgetAccentable()
                Text("\(entry.minutes) of \(entry.goal) min")
                if entry.streak > 0 { Text("🔥 \(entry.streak)-day streak").font(.caption) }
            }
        case .accessoryCorner:
            Image(systemName: "music.note")
                .widgetLabel { Gauge(value: progress) { Text("min") } }
        default:
            Gauge(value: progress) {
                Image(systemName: entry.isPracticing ? "waveform" : "music.note")
            } currentValueLabel: {
                Text("\(entry.minutes)")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}
