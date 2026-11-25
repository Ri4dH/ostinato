import Foundation
import PracticeKit

/// Sample state for watch UI tests and App Store screenshots (`-demoData`).
/// Debug builds only; always off in Release.
enum WatchDemo {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoData")
        #else
        false
        #endif
    }

    #if DEBUG
    static var wantsSession: Bool { ProcessInfo.processInfo.arguments.contains("-demoSession") }

    static let violin = InstrumentRef(id: UUID(), name: "Violin", colorHex: "#008300", symbolName: "music.quarternote.3")
    static let piano = InstrumentRef(id: UUID(), name: "Piano", colorHex: "#2A78D6", symbolName: "pianokeys")
    static let items = [
        WatchItem(id: UUID(), title: "Scales: G, D, A major", instrumentID: violin.id),
        WatchItem(id: UUID(), title: "Partita No. 2 – Chaconne", instrumentID: violin.id),
        WatchItem(id: UUID(), title: "Kreutzer Étude No. 2", instrumentID: violin.id),
        WatchItem(id: UUID(), title: "Meditation from Thaïs", instrumentID: violin.id)
    ]

    static func context(now: Date = Date()) -> PhoneContext {
        PhoneContext(instruments: [violin, piano], items: items, goal: GoalSettings(dailyMinutes: 30, daysPerWeek: 5),
                     todaySeconds: 21 * 60, todayDate: now, streak: 6, lastInstrumentID: violin.id,
                     activeSession: nil, updatedAt: now)
    }

    /// A session that has been running for a while, now on the Chaconne.
    static func session(now: Date = Date()) -> ActiveSession {
        let begin = now.addingTimeInterval(-(18 * 60 + 24))
        nonisolated(unsafe) var clock = begin
        let engine = SessionEngine(now: { clock })
        var session = engine.start(instrument: violin, target: .item(items[0].id, title: items[0].title), source: .watch)
        clock = begin.addingTimeInterval(11 * 60)
        engine.switchTo(.item(items[1].id, title: items[1].title), in: &session)
        return session
    }
    #endif
}
