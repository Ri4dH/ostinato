import Foundation
import SwiftData
import Testing
@testable import PracticeKit

@Suite("Watch sync")
@MainActor
struct WatchSyncTests {
    @Test func offlineWatchSessionArrivesExactlyOnce() throws {
        let container = try makeTestContainer()
        let phone = SessionController(engine: SessionEngine(), store: InMemoryActiveSessionStore())
        let handler = PhoneSyncHandler(context: container.mainContext, controller: phone)

        // Watch records a session with no phone nearby.
        let clock = TestClock()
        var watchSession = clock.engine.start(instrument: nil, target: scales, source: .watch)
        clock.advance(900)
        clock.engine.switchTo(pieceA, in: &watchSession)
        clock.advance(600)
        var outbox = WatchOutbox()
        let finished = clock.engine.finish(watchSession)
        outbox.enqueue(finished)
        outbox.enqueue(finished)   // double-tap on Finish
        #expect(outbox.pending.count == 1)

        // Reconnect: the queued transfer and a manual resend both arrive.
        let message = try #require(WatchMessage.decode(try WatchMessage.finishedSession(finished).encoded()))
        #expect(handler.handle(message) == .reply(.ack([finished.id])))
        #expect(handler.handle(message) == .reply(.ack([finished.id])))
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PracticeSession>()) == 1)

        outbox.acknowledge([finished.id])
        #expect(outbox.pending.isEmpty)
    }

    @Test func sessionStartedOnPhoneCanBeSwitchedAndFinishedFromWatch() throws {
        let container = try makeTestContainer()
        let clock = TestClock()
        let phone = SessionController(engine: clock.engine, store: InMemoryActiveSessionStore())
        let handler = PhoneSyncHandler(context: container.mainContext, controller: phone)
        let started = phone.start(instrument: nil, target: scales)

        // Watch receives it, switches item, sends live state back.
        var onWatch = started
        clock.advance(300)
        clock.engine.switchTo(pieceA, in: &onWatch)
        #expect(handler.handle(.activeSession(onWatch)) == .none)
        #expect(phone.active?.currentTarget == pieceA)

        // Watch finishes it.
        clock.advance(300)
        let finished = clock.engine.finish(onWatch)
        _ = handler.handle(.finishedSession(finished))
        #expect(phone.active == nil)
        let saved = try #require(try container.mainContext.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(saved.activeDuration == 600)
    }

    @Test func outboxCountsUnsyncedTimeForToday() {
        let ny = calendar("America/New_York")
        var outbox = WatchOutbox()
        let today = FinishedSession(id: UUID(), startDate: date(2026, 3, 2, 9), endDate: date(2026, 3, 2, 9, 30),
                                    activeDuration: 1800, source: .watch, instrumentID: nil, segments: [], pauses: [])
        var yesterday = today
        yesterday.id = UUID()
        yesterday.startDate = date(2026, 3, 1, 9)
        outbox.enqueue(today)
        outbox.enqueue(yesterday)
        #expect(outbox.unsyncedSeconds(on: date(2026, 3, 2, 20), calendar: ny) == 1800)
    }
}

@Suite("Weekly summary")
struct WeeklySummaryTests {
    let ny = calendar("America/New_York")

    @Test func inputStaysWithinTokenBudget() {
        // A heavy week: many items with very long titles and notes.
        var titles: [UUID: (title: String, category: ItemCategory)] = [:]
        var records: [SessionRecord] = []
        for i in 0..<40 {
            let id = UUID()
            titles[id] = (String(repeating: "Very long piece title \(i) ", count: 10), .piece)
            records.append(SessionRecord(startDate: date(2026, 3, 2 + i % 6, 10 + i % 8), activeDuration: 3600,
                                         rating: 4, focus: 3,
                                         segments: [SegmentRecord(itemID: id, category: .piece, duration: 3600)]))
        }
        let notes = (0..<50).map { _ in String(repeating: "Long practice note text. ", count: 40) }
        let input = WeeklySummaryInput.make(records: records, itemTitles: titles, notes: notes,
                                            goal: .default, now: date(2026, 3, 7), calendar: ny)
        #expect(input.topItems.count == WeeklySummaryInput.maxItems)
        #expect(input.notes.count == WeeklySummaryInput.maxNotes)
        #expect(input.estimatedTokens < 2_000)
    }

    @Test func rulesBasedSummaryIsSpecific() {
        let scalesID = UUID(), chaconne = UUID()
        let records = [
            SessionRecord(startDate: date(2026, 3, 2), activeDuration: 3000, focus: 4,
                          segments: [SegmentRecord(itemID: chaconne, category: .piece, duration: 2800),
                                     SegmentRecord(itemID: scalesID, category: .scale, duration: 200)]),
            SessionRecord(startDate: date(2026, 2, 24), activeDuration: 1200)
        ]
        let input = WeeklySummaryInput.make(
            records: records, itemTitles: [chaconne: ("Chaconne", .piece), scalesID: ("G major", .scale)],
            notes: [], goal: GoalSettings(daysPerWeek: 1), now: date(2026, 3, 4), calendar: ny)
        let summary = RulesBasedSummary.make(input)
        #expect(summary.headline.contains("Chaconne"))
        #expect(summary.observations.count <= 3)
        #expect(summary.suggestion.contains("7%"))
        #expect(!summary.isGenerated)
    }

    @Test func emptyWeekIsGentle() {
        let input = WeeklySummaryInput.make(records: [], itemTitles: [:], notes: [], goal: .default,
                                            now: date(2026, 3, 4), calendar: ny)
        let summary = RulesBasedSummary.make(input)
        #expect(summary.observations.isEmpty)
        #expect(!summary.suggestion.isEmpty)
    }
}

/// String catalogs are compiled by Xcode builds only; `swift test` on the
/// command line copies the raw .xcstrings, so plural rules can't apply there.
private var catalogIsCompiled: Bool {
    let bundle = PracticeKitResources.bundle
    return (try? FileManager.default.subpathsOfDirectory(atPath: bundle.bundlePath))?
        .contains { $0.hasSuffix(".stringsdict") } ?? false
}

@Suite("Localized plurals", .enabled(if: catalogIsCompiled, "Run through Xcode (compiled string catalog)"))
struct PluralTests {
    @Test func summarySuggestionUsesSingular() {
        let input = WeeklySummaryInput(weekStart: Date(), totalMinutes: 30, previousWeekMinutes: 0, daysPracticed: 2,
                                       goalDaysPerWeek: 3, goalDailyMinutes: 20, streak: 2, topItems: [],
                                       categoryShares: [:], averageRating: nil, averageFocus: nil, notes: [])
        #expect(RulesBasedSummary.make(input).suggestion == "Add 1 more short session to reach your weekly goal.")
    }
}
