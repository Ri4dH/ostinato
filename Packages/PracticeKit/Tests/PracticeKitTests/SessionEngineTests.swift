import Foundation
import Testing
@testable import PracticeKit

@Suite("Session engine")
struct SessionEngineTests {
    @Test func elapsedIgnoresPauses() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        clock.advance(600)            // 10 min running
        engine.pause(&s)
        clock.advance(120)            // 2 min paused
        #expect(s.elapsed(at: clock.now) == 600)
        engine.resume(&s)
        clock.advance(300)            // 5 min running
        engine.pause(&s)
        clock.advance(60)
        engine.resume(&s)
        clock.advance(30)
        #expect(s.elapsed(at: clock.now) == 930)
        #expect(!s.isPaused)
    }

    @Test func pauseAndResumeAreIdempotent() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        #expect(engine.resume(&s) == false)
        #expect(engine.pause(&s))
        #expect(engine.pause(&s) == false)
        #expect(s.pauses.count == 1)
    }

    @Test func segmentDurationsSumToSessionDuration() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, target: scales, source: .phone)
        clock.advance(600)
        engine.switchTo(pieceA, in: &s)
        clock.advance(400)
        engine.pause(&s)
        clock.advance(200)
        engine.switchTo(pieceB, in: &s)   // switch while paused
        clock.advance(100)
        engine.resume(&s)
        clock.advance(1_234.5)
        engine.pause(&s)
        clock.advance(50)                  // finish while paused

        let finished = engine.finish(s)
        let sum = finished.segments.reduce(0) { $0 + $1.activeDuration }
        #expect(abs(sum - finished.activeDuration) < 1)
        #expect(finished.activeDuration == 600 + 400 + 1_234.5)
        #expect(finished.segments.map(\.activeDuration) == [600, 400, 1_234.5])
        #expect(finished.segments.map(\.target) == [scales, pieceA, pieceB])
        #expect(finished.pauses.count == 2)
        #expect(finished.pauses.allSatisfy { $0.end >= $0.start })
    }

    @Test func segmentsAreContiguous() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        for target in [pieceA, pieceB, scales, pieceA] {
            clock.advance(90)
            engine.switchTo(target, in: &s)
        }
        clock.advance(10)
        let f = engine.finish(s)
        for (a, b) in zip(f.segments, f.segments.dropFirst()) {
            #expect(a.endDate == b.startDate)
        }
        #expect(f.segments.first?.startDate == f.startDate)
        #expect(f.segments.last?.endDate == f.endDate)
    }

    @Test func switchingToSameTargetDoesNothing() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, target: pieceA, source: .phone)
        clock.advance(30)
        #expect(engine.switchTo(pieceA, in: &s) == false)
        #expect(s.segments.count == 1)
    }

    @Test func rapidSwitchesRetargetInsteadOfCreatingEmptySegments() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, target: scales, source: .phone)
        clock.advance(120)
        engine.switchTo(pieceA, in: &s)
        clock.advance(0.3)
        engine.switchTo(pieceB, in: &s)   // quick correction
        #expect(s.segments.count == 2)
        #expect(s.currentTarget == pieceB)
        clock.advance(0.2)
        engine.switchTo(scales, in: &s)   // back to the previous one: merge
        #expect(s.segments.count == 1)
        #expect(s.segments[0].endDate == nil)
    }

    @Test func clockJumpingBackwardNeverReducesElapsed() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        clock.advance(600)
        engine.switchTo(pieceA, in: &s)
        clock.advance(-3_600)              // user changes the clock back an hour
        engine.switchTo(pieceB, in: &s)
        let f = engine.finish(s)
        #expect(f.activeDuration >= 600)
        #expect(f.segments.allSatisfy { $0.activeDuration >= 0 })
    }

    @Test func timerReferenceDateIsStableWhileRunning() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        clock.advance(100)
        engine.pause(&s)
        clock.advance(50)
        engine.resume(&s)
        let ref1 = s.timerReferenceDate(at: clock.now)
        clock.advance(500)
        let ref2 = s.timerReferenceDate(at: clock.now)
        #expect(ref1 == ref2)
        #expect(clock.now.timeIntervalSince(ref2) == s.elapsed(at: clock.now))
    }

    @Test func longRunningDetection() {
        let clock = TestClock()
        let engine = clock.engine
        let s = engine.start(instrument: nil, source: .phone)
        clock.advance(4 * 3600 - 1)
        #expect(!engine.isLongRunning(s))
        clock.advance(1)
        #expect(engine.isLongRunning(s))
    }

    @Test func quickNotesBecomeSessionNotes() {
        let clock = TestClock()
        let engine = clock.engine
        var s = engine.start(instrument: nil, source: .phone)
        engine.addNote("  Bar 32 shift is sharp ", to: &s)
        engine.addNote("   ", to: &s)
        engine.addNote("Try slower bowing", to: &s)
        #expect(engine.finish(s).notes == "Bar 32 shift is sharp\nTry slower bowing")
    }
}

@Suite("Calendar edge cases")
struct SessionCalendarTests {
    @Test func sessionCrossingMidnightCountsTowardStartDay() {
        let ny = calendar("America/New_York")
        let clock = TestClock(date(2026, 3, 10, 23, 30))
        let engine = clock.engine
        let s = engine.start(instrument: nil, source: .phone)
        clock.advance(3600)
        let f = engine.finish(s)
        #expect(ny.component(.day, from: f.endDate) == 11)
        #expect(s.practiceDay(in: ny) == ny.startOfDay(for: date(2026, 3, 10)))
    }

    @Test func dstSpringForwardDoesNotChangeElapsed() {
        // US DST starts 2026-03-08 at 2:00 AM; wall clock skips an hour.
        let clock = TestClock(date(2026, 3, 8, 1, 30))
        let engine = clock.engine
        let s = engine.start(instrument: nil, source: .phone)
        clock.advance(3600)
        let f = engine.finish(s)
        #expect(f.activeDuration == 3600)
        #expect(calendar("America/New_York").component(.hour, from: f.endDate) == 3)
    }

    @Test func dstFallBackDoesNotChangeElapsed() {
        let clock = TestClock(date(2026, 11, 1, 1, 10))
        let engine = clock.engine
        let s = engine.start(instrument: nil, source: .phone)
        clock.advance(3600)
        #expect(engine.finish(s).activeDuration == 3600)
    }

    @Test func timezoneChangeMidSessionKeepsDurationAndStartDay() {
        let clock = TestClock(date(2026, 6, 1, 22, 0, tz: "Europe/Berlin"))
        let engine = clock.engine
        let s = engine.start(instrument: nil, source: .phone)
        clock.advance(7200)
        let f = engine.finish(s)
        #expect(f.activeDuration == 7200)
        // The day is fixed by the start instant in the calendar used for display.
        let berlin = calendar("Europe/Berlin")
        #expect(s.practiceDay(in: berlin) == berlin.startOfDay(for: date(2026, 6, 1, tz: "Europe/Berlin")))
    }
}
