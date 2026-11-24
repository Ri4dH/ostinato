import Foundation
import Testing
@testable import PracticeKit

@Suite("Phone/watch concurrent sessions")
struct SessionMergerTests {
    @Test func sameSessionKeepsNewestCopy() {
        let clock = TestClock()
        let engine = clock.engine
        let base = engine.start(instrument: nil, source: .phone)
        var remote = base
        clock.advance(60)
        engine.switchTo(pieceA, in: &remote)
        #expect(SessionMerger.resolve(local: base, remote: remote) == .keep(remote))
        #expect(SessionMerger.resolve(local: remote, remote: base) == .keep(remote))
    }

    @Test func earliestStartWins() {
        let clock = TestClock()
        let engine = clock.engine
        let phone = engine.start(instrument: nil, target: scales, source: .phone)
        clock.advance(5)
        let watch = engine.start(instrument: nil, target: pieceA, source: .watch)

        guard case let .conflict(winner, loser) = SessionMerger.resolve(local: watch, remote: phone) else {
            Issue.record("expected conflict")
            return
        }
        #expect(winner.id == phone.id)
        #expect(loser.id == watch.id)
    }

    @Test func mergeProducesOneContiguousSession() {
        let clock = TestClock()
        let engine = clock.engine
        var phone = engine.start(instrument: nil, target: scales, source: .phone)
        clock.advance(120)
        var watch = engine.start(instrument: nil, target: pieceA, source: .watch)
        clock.advance(300)
        engine.switchTo(pieceB, in: &phone)
        clock.advance(200)
        engine.switchTo(scales, in: &watch)

        let merged = SessionMerger.merge(winner: phone, loser: watch)
        #expect(merged.id == phone.id)
        #expect(merged.startDate == phone.startDate)
        #expect(merged.segments.map(\.target) == [scales, pieceA, pieceB, scales])
        for (a, b) in zip(merged.segments, merged.segments.dropFirst()) {
            #expect(a.endDate == b.startDate)
        }
        #expect(merged.segments.last?.endDate == nil)

        clock.advance(100)
        let finished = engine.finish(merged)
        let sum = finished.segments.reduce(0) { $0 + $1.activeDuration }
        #expect(abs(sum - finished.activeDuration) < 1)
        #expect(finished.activeDuration == 720)
    }

    @Test @MainActor func controllerReportsConflictAndResolves() {
        let clock = TestClock()
        let controller = SessionController(engine: clock.engine, store: InMemoryActiveSessionStore())
        let local = controller.start(instrument: nil, target: scales)
        clock.advance(10)
        let remote = clock.engine.start(instrument: nil, target: pieceA, source: .watch)

        guard case let .conflict(winner, loser) = controller.applyRemote(remote) else {
            Issue.record("expected conflict")
            return
        }
        #expect(winner.id == local.id)
        controller.resolveConflict(winner: winner, loser: loser, merge: false)
        #expect(controller.active?.id == local.id)
        #expect(controller.active?.segments.count == 1)
    }

    @Test @MainActor func remoteSessionAdoptedWhenIdle() {
        let clock = TestClock()
        let controller = SessionController(engine: clock.engine, store: InMemoryActiveSessionStore())
        let remote = clock.engine.start(instrument: nil, source: .watch)
        #expect(controller.applyRemote(remote) == nil)
        #expect(controller.active == remote)
        controller.applyRemoteEnd(sessionID: remote.id)
        #expect(controller.active == nil)
    }
}
