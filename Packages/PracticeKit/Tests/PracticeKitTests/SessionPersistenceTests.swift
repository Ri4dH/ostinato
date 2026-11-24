import Foundation
import SwiftData
import Testing
@testable import PracticeKit

@Suite("Persistence and restore")
@MainActor
struct SessionPersistenceTests {
    @Test func restoreAfterSimulatedKill() throws {
        let dir = tempDirectory()
        let clock = TestClock()
        let store = FileActiveSessionStore(directory: dir)

        var controller: SessionController? = SessionController(engine: clock.engine, store: store)
        controller?.start(instrument: nil, target: scales)
        clock.advance(300)
        controller?.switchTo(pieceA)
        clock.advance(100)
        controller?.pause()
        let before = controller?.active
        controller = nil   // "kill" the app

        clock.advance(1_000)
        let relaunched = SessionController(engine: clock.engine, store: FileActiveSessionStore(directory: dir))
        #expect(relaunched.active == before)
        #expect(relaunched.active?.isPaused == true)
        #expect(relaunched.active?.elapsed(at: clock.now) == 400)
    }

    @Test func onlyOneActiveSession() {
        let clock = TestClock()
        let controller = SessionController(engine: clock.engine, store: InMemoryActiveSessionStore())
        let first = controller.start(instrument: nil)
        clock.advance(10)
        let second = controller.start(instrument: nil)
        #expect(first.id == second.id)
    }

    @Test func finishKeepsSnapshotUntilSaved() throws {
        let store = InMemoryActiveSessionStore()
        let clock = TestClock()
        let controller = SessionController(engine: clock.engine, store: store)
        controller.start(instrument: nil)
        clock.advance(60)
        let finished = try #require(controller.finish())
        #expect(store.load() != nil)
        controller.markSaved(finished)
        #expect(store.load() == nil)
        #expect(controller.active == nil)
    }

    @Test func observersSeeEveryChange() {
        let clock = TestClock()
        let controller = SessionController(engine: clock.engine, store: InMemoryActiveSessionStore())
        var events: [String] = []
        controller.addObserver { event in
            switch event {
            case .started: events.append("start")
            case .changed: events.append("change")
            case .finished: events.append("finish")
            case .discarded: events.append("discard")
            case .restored: events.append("restore")
            }
        }
        controller.start(instrument: nil)
        clock.advance(5)
        controller.switchTo(pieceA)
        controller.switchTo(pieceA)   // no-op, no event
        controller.togglePause()
        controller.discard()
        #expect(events == ["start", "change", "change", "discard"])
    }

    @Test func writerIsIdempotentAndLinksItems() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let instrument = Instrument(name: "Violin")
        let item = PracticeItem(title: "Chaconne", instrument: instrument)
        context.insert(instrument)
        context.insert(item)
        try context.save()

        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: InstrumentRef(instrument), target: .label("Warm-up"), source: .watch)
        clock.advance(300)
        engine.switchTo(.item(item.id, title: item.title), in: &s)
        clock.advance(900)
        var finished = engine.finish(s)
        finished.rating = 9
        finished.tags = ["Lesson prep", " lesson prep ", "", "Bach"]

        let take = Recording(audioFileName: "take.m4a")
        take.sessionRefID = finished.id
        take.segmentRefID = finished.segments.last?.id
        context.insert(take)

        try SessionWriter.insert(finished, into: context)
        try SessionWriter.insert(finished, into: context)   // duplicate delivery
        #expect(take.session?.id == finished.id)
        #expect(take.item?.id == item.id)

        let sessions = try context.fetch(FetchDescriptor<PracticeSession>())
        #expect(sessions.count == 1)
        let saved = try #require(sessions.first)
        #expect(saved.instrument?.name == "Violin")
        #expect(saved.source == .watch)
        #expect(saved.rating == 5)
        #expect(saved.tags == ["Lesson prep", "Bach"])
        #expect(saved.sortedSegments.map(\.displayTitle) == ["Warm-up", "Chaconne"])
        #expect(saved.activeDuration == 1_200)
        #expect(item.totalPracticed == 900)
    }
}
