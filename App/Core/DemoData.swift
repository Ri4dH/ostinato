import Foundation
import PracticeKit
import SwiftData

/// Realistic sample data for UI tests, accessibility audits and App Store
/// screenshots. Only used with the `-demoData` launch argument.
@MainActor
enum DemoData {
    static func seed(into context: ModelContext, now: Date = Date()) {
        let violin = Instrument(preset: InstrumentPreset.preset(forKey: "violin")!, sortIndex: 0)
        let piano = Instrument(preset: InstrumentPreset.preset(forKey: "piano")!, sortIndex: 1)
        [violin, piano].forEach(context.insert)

        let items: [PracticeItem] = [
            PracticeItem(title: "Scales: G, D, A major", category: .scale, status: .maintaining, instrument: violin),
            PracticeItem(title: "Partita No. 2 – Chaconne", composer: "J. S. Bach", category: .piece,
                         status: .learning, targetTempo: 76, instrument: violin),
            PracticeItem(title: "Kreutzer Étude No. 2", composer: "R. Kreutzer", category: .exercise,
                         status: .polishing, targetTempo: 100, instrument: violin),
            PracticeItem(title: "Meditation from Thaïs", composer: "J. Massenet", category: .piece,
                         status: .performanceReady, instrument: violin),
            PracticeItem(title: "Nocturne Op. 9 No. 2", composer: "F. Chopin", category: .piece,
                         status: .learning, instrument: piano),
            PracticeItem(title: "Hanon No. 1", category: .technique, status: .maintaining, instrument: piano)
        ]
        items.enumerated().forEach { $1.sortIndex = $0; context.insert($1) }

        let calendar = Calendar.current
        var generator = SeededGenerator(seed: 42)
        let notes = ["Shifts in bars 33–40 cleaner at 60.", "Slow bows on open strings first.",
                     "Recorded the chords; intonation drifts on the high E.", "", "", ""]
        for daysAgo in (0..<42).reversed() {
            // About five days a week, sometimes twice.
            guard Int.random(in: 0..<7, using: &generator) < 5 || daysAgo == 0 else { continue }
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) else { continue }
            let useViolin = Int.random(in: 0..<5, using: &generator) > 0
            let pool = useViolin ? Array(items[0..<4]) : Array(items[4..<6])
            let hour = daysAgo == 0 ? max(7, calendar.component(.hour, from: now) - 2) : Int.random(in: 7...20, using: &generator)
            var start = calendar.date(bySettingHour: hour, minute: Int.random(in: 0..<60, using: &generator), second: 0, of: day) ?? day
            if start > now { start = now.addingTimeInterval(-3_600) }
            var segments: [ManualSegment] = [ManualSegment(target: .item(pool[0].id, title: pool[0].title),
                                                           minutes: Int.random(in: 8...15, using: &generator))]
            for item in pool.dropFirst().shuffled(using: &generator).prefix(Int.random(in: 1...2, using: &generator)) {
                segments.append(ManualSegment(target: .item(item.id, title: item.title), minutes: Int.random(in: 10...30, using: &generator)))
            }
            guard let finished = ManualSessionBuilder.make(
                start: start, segments: segments, instrumentID: (useViolin ? violin : piano).id,
                source: daysAgo % 6 == 0 ? .watch : .phone,
                rating: Int.random(in: 3...5, using: &generator), focus: Int.random(in: 2...5, using: &generator),
                notes: notes.randomElement(using: &generator) ?? "",
                tags: daysAgo % 7 == 1 ? ["Lesson prep"] : [])
            else { continue }
            _ = try? SessionWriter.insert(finished, into: context)
        }

        // Tempo progress on the Chaconne and the étude.
        for (index, bpm) in [52, 56, 58, 60, 63, 66, 68].enumerated() {
            let date = calendar.date(byAdding: .day, value: -40 + index * 6, to: now) ?? now
            context.insert(items[1].logTempo(bpm, source: index % 3 == 0 ? .manual : .metronome, date: date))
        }
        for (index, bpm) in [80, 84, 88, 92, 94].enumerated() {
            let date = calendar.date(byAdding: .day, value: -30 + index * 7, to: now) ?? now
            context.insert(items[2].logTempo(bpm, source: .metronome, date: date))
        }
        try? context.save()
    }
}

/// Deterministic random numbers so demo data looks the same every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
