import Foundation
import SwiftData
import Testing
@testable import PracticeKit

@Suite("Store performance", .serialized)
@MainActor
struct StorePerformanceTests {
    /// Spec §14: 10,000 sessions / 50,000 segments; the Stats tab's work
    /// (fetch + map + aggregate) should stay fast.
    @Test func statsLoadFromStoreWithTenThousandSessions() async throws {
        let dir = tempDirectory()
        let config = ModelConfiguration(schema: PracticeStore.schema, url: dir.appending(path: "perf.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: PracticeStore.schema, configurations: config)
        let context = container.mainContext
        context.autosaveEnabled = false

        let items = (0..<200).map { PracticeItem(title: "Item \($0)", category: $0 % 3 == 0 ? .scale : .piece) }
        items.forEach(context.insert)
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        for i in 0..<10_000 {
            let s = PracticeSession(startDate: start.addingTimeInterval(Double(i) * 5 * 3600), activeDuration: 3000)
            s.rating = i % 5 + 1
            context.insert(s)
            s.segments = (0..<5).map { j in
                let seg = SessionSegment(startDate: s.startDate.addingTimeInterval(Double(j) * 600),
                                         activeDuration: 600, sortIndex: j, item: items[(i + j) % items.count])
                context.insert(seg)
                return seg
            }
            if i % 1_000 == 999 { try context.save() }
        }
        try context.save()

        // Fresh context, as on app launch.
        let readContext = ModelContext(container)
        let clock = ContinuousClock()
        var records: [SessionRecord] = []
        let loadTime = clock.measure {
            records = (try? SessionRecordLoader.load(from: readContext)) ?? []
        }
        let stats = StatsCalculator(calendar: calendar("America/New_York"))
        let now = records.map(\.startDate).max()!
        let computeTime = clock.measure {
            let all = StatsRange.all.interval(containing: now, calendar: stats.calendar, earliest: start)
            _ = stats.bucketTotals(records, in: all, bucket: .month)
            _ = stats.topItems(records)
            _ = stats.totalsByCategory(records)
            _ = stats.streak(records, goal: .default, now: now)
            _ = stats.weeklyAverages(records, in: all)
        }
        print("PERF load \(loadTime) compute \(computeTime) for \(records.count) sessions")
        #expect(records.count == 10_000)
        #expect(records.reduce(0) { $0 + $1.segments.count } == 50_000)
        #expect(computeTime < .milliseconds(500))

        // The full store read is slow (SwiftData materializes 60k objects), which
        // is why it only ever runs on a background actor. The cache the UI reads
        // must be fast.
        let cacheURL = dir.appending(path: "records.plist")
        let store = StatsRecordStore(cacheURL: cacheURL)
        store.rebuild(from: container)
        await store.waitForRebuild()
        #expect(store.records.count == 10_000)
        try await Task.sleep(for: .milliseconds(500))   // cache write is detached
        var reopened: StatsRecordStore?
        let cacheTime = clock.measure { reopened = StatsRecordStore(cacheURL: cacheURL) }
        print("PERF store load \(loadTime), cache load \(cacheTime)")
        #expect(reopened?.records.count == 10_000)
        #expect(cacheTime < .milliseconds(500))

        // Same answer as walking relationships.
        let sample = try readContext.fetch(FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startDate)]))
            .prefix(50).map(SessionRecord.init)
        for (fast, slow) in zip(records.prefix(50), sample) {
            #expect(fast.id == slow.id)
            #expect(Set(fast.segments.map(\.itemID)) == Set(slow.segments.map(\.itemID)))
            #expect(fast.segments.reduce(0) { $0 + $1.duration } == slow.segments.reduce(0) { $0 + $1.duration })
        }
    }
}

@Suite("Stats record cache")
@MainActor
struct StatsRecordStoreTests {
    @Test func upsertRemoveAndPersist() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let url = tempDirectory().appending(path: "records.plist")
        let store = StatsRecordStore(cacheURL: url)
        let clock = TestClock(date(2026, 3, 2))
        var s = clock.engine.start(instrument: nil, target: scales, source: .phone)
        clock.advance(600)
        clock.engine.switchTo(pieceA, in: &s)
        clock.advance(600)
        let session = try SessionWriter.insert(clock.engine.finish(s), into: context)

        store.upsert(session)
        #expect(store.records.map(\.activeDuration) == [1200])
        session.sortedSegments.first?.activeDuration = 300
        session.recomputeDuration()
        store.upsert(session)
        #expect(store.records.count == 1)
        #expect(store.records.first?.activeDuration == 900)

        try await Task.sleep(for: .milliseconds(300))
        #expect(StatsRecordStore(cacheURL: url).records.first?.activeDuration == 900)

        store.remove(sessionID: session.id)
        #expect(store.records.isEmpty)
    }

    @Test func rebuildMatchesStore() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        for day in 1...5 {
            let finished = ManualSessionBuilder.make(
                start: date(2026, 3, day), segments: [ManualSegment(target: .general, minutes: day * 10)], instrumentID: nil)!
            try SessionWriter.insert(finished, into: context)
        }
        let store = StatsRecordStore(cacheURL: nil)
        store.rebuild(from: container)
        await store.waitForRebuild()
        #expect(store.records.map(\.activeDuration) == [600, 1200, 1800, 2400, 3000])
        #expect(!store.isRebuilding)
    }
}
