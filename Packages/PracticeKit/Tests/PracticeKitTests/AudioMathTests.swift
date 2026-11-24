import Foundation
import Testing
@testable import PracticeKit

private func sine(_ frequency: Double, sampleRate: Double = 48_000, count: Int = 4_096,
                  harmonics: [Double] = [1], amplitude: Float = 0.5) -> [Float] {
    (0..<count).map { i in
        let t = Double(i) / sampleRate
        let v = harmonics.enumerated().reduce(0.0) { $0 + $1.element * sin(2 * .pi * frequency * Double($1.offset + 1) * t) }
        return Float(v) * amplitude / Float(harmonics.reduce(0, +))
    }
}

@Suite("Tuner math")
struct TunerTests {
    @Test(arguments: [440.0, 415.0, 82.41, 196.0, 261.63, 659.26, 1_046.5, 1_760.0])
    func detectsSustainedTonesWithinOneCent(frequency: Double) throws {
        let detector = PitchDetector(sampleRate: 48_000)
        let estimate = try #require(detector.detect(sine(frequency, count: 4_096)))
        #expect(abs(NoteMath.cents(from: frequency, to: estimate.frequency)) < 1)
    }

    @Test func detectsHarmonicRichTones() throws {
        let detector = PitchDetector(sampleRate: 44_100)
        let tone = sine(146.83, sampleRate: 44_100, count: 4_096, harmonics: [1, 0.8, 0.6, 0.5, 0.3])
        let estimate = try #require(detector.detect(tone))
        #expect(abs(NoteMath.cents(from: 146.83, to: estimate.frequency)) < 1)
    }

    @Test func silenceReturnsNil() {
        let detector = PitchDetector(sampleRate: 48_000)
        #expect(detector.detect([Float](repeating: 0, count: 4_096)) == nil)
        #expect(detector.detect(sine(440, amplitude: 0.001)) == nil)
    }

    @Test func transpositionShowsWrittenPitch() throws {
        // B♭ clarinet playing concert B♭4 reads as written C5.
        let concertBb4 = NoteMath.frequency(midi: 70)
        let reading = try #require(NoteMath.reading(frequency: concertBb4, transposition: -2))
        #expect(reading.name(written: true) == "C")
        #expect(reading.octave(written: true) == 5)
        #expect(reading.name(written: false) == "B♭")
        #expect(abs(reading.cents) < 0.001)

        // Alto sax (−9): concert E♭4 → written C5.
        let altoReading = try #require(NoteMath.reading(frequency: NoteMath.frequency(midi: 63), transposition: -9))
        #expect(altoReading.name(written: true) == "C")
    }

    @Test func respectsA4Reference() throws {
        let reading = try #require(NoteMath.reading(frequency: 415, a4: 415))
        #expect(reading.name(written: false) == "A")
        #expect(abs(reading.cents) < 0.001)
        let at440 = try #require(NoteMath.reading(frequency: 415, a4: 440))
        #expect(at440.name(written: false) == "A♭")
        #expect(abs(at440.cents - (-1.3)) < 1)
    }

    @Test func centsAndOctaves() {
        #expect(abs(NoteMath.cents(from: 440, to: 880) - 1200) < 0.0001)
        #expect(NoteMath.octave(midi: 60) == 4)
        #expect(NoteMath.name(midi: 61) == "C♯")
        #expect(StringTuning.tunings(forPreset: "violin").first?.nearestString(to: 68.7) == 69)
    }

    @Test func smootherRejectsOutliersAndFollowsNoteChanges() {
        var smoother = PitchSmoother()
        var last = 0.0
        for f in [440.0, 440.4, 439.8, 880.0, 440.2, 440.1] { last = smoother.add(f) }
        #expect(abs(NoteMath.cents(from: 440, to: last)) < 2)   // octave glitch ignored
        for _ in 0..<8 { last = smoother.add(493.88) }            // real change to B
        #expect(abs(NoteMath.cents(from: 493.88, to: last)) < 3)
    }
}

@Suite("Metronome math")
struct MetronomeTests {
    @Test func noDriftOverLongRuns() {
        let scheduler = ClickScheduler(settings: MetronomeSettings(bpm: 133), sampleRate: 48_000)
        // After exactly 133 beats one minute has passed: 48,000 × 60 frames.
        #expect(scheduler.frame(ofTick: 133) == 2_880_000)
        #expect(scheduler.frame(ofTick: 133 * 60) == 2_880_000 * 60)
        // Bar lengths may differ by one frame from rounding but sum exactly.
        let total = (0..<1_000).reduce(Int64(0)) { $0 + scheduler.barLength(Int64($1)) }
        #expect(total == scheduler.frame(ofBar: 1_000))
    }

    @Test func accentsAndSubdivisions() {
        let settings = MetronomeSettings(bpm: 120, beatsPerBar: 3, subdivision: .eighths)
        let clicks = ClickScheduler(settings: settings, sampleRate: 48_000).clicks(inBar: 5)
        #expect(clicks.map(\.kind) == [.accent, .subdivision, .beat, .subdivision, .beat, .subdivision])
        #expect(clicks.map(\.frame) == [0, 12_000, 24_000, 36_000, 48_000, 60_000])
    }

    @Test func compoundMetersGroupInThrees() {
        let settings = MetronomeSettings(bpm: 180, beatsPerBar: 6, beatUnit: 8)
        let kinds = ClickScheduler(settings: settings, sampleRate: 48_000).clicks(inBar: 0).map(\.kind)
        #expect(kinds == [.accent, .subdivision, .subdivision, .beat, .subdivision, .subdivision])
    }

    @Test func bpmIsClamped() {
        var s = MetronomeSettings(bpm: 5)
        #expect(s.bpm == 20)
        s.bpm = 999
        #expect(s.bpm == 300)
    }

    @Test func tapTempo() {
        var tapper = TapTempo()
        #expect(tapper.tap(at: 10) == nil)
        #expect(tapper.tap(at: 10.5) == 120)
        #expect(tapper.tap(at: 11.0) == 120)
        #expect(tapper.tap(at: 11.7) == 106)
        #expect(tapper.tap(at: 20) == nil)  // long gap resets
    }
}

@Suite("Drone")
struct DroneTests {
    @Test func allTwelveKeysWithTransposition() {
        let concertA3 = DroneSettings(pitchClass: 9, octave: 3, useConcertPitch: true)
        #expect(abs(concertA3.frequencies[0] - 220) < 0.001)
        // Written C4 on a B♭ trumpet sounds concert B♭3.
        let trumpetC = DroneSettings(pitchClass: 0, octave: 4, transposition: -2)
        #expect(trumpetC.rootConcertMidi == 58)
        let fifth = DroneSettings(pitchClass: 2, octave: 3, voicing: .rootFifthOctave, a4: 415, useConcertPitch: true)
        #expect(fifth.frequencies.count == 3)
        #expect(abs(NoteMath.cents(from: fifth.frequencies[0], to: fifth.frequencies[1]) - 700) < 0.001)
        #expect(Set((0..<12).map { DroneSettings(pitchClass: $0, useConcertPitch: true).rootConcertMidi }).count == 12)
    }

    @Test func fadesInAndOutWithoutClicks() {
        var synth = DroneSynth(sampleRate: 48_000)
        synth.configure(DroneSettings(timbre: .cello, voicing: .rootFifth, volume: 1))
        var buffer = [Float](repeating: 0, count: 48_000)
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0) }
        // Starts from silence; no sample-to-sample jump bigger than a sane slope.
        #expect(abs(buffer[0]) < 0.001)
        let maxStep = zip(buffer, buffer.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        #expect(maxStep < 0.2)
        #expect(buffer.map(abs).max()! <= 1)
        synth.fadeOut()
        buffer.withUnsafeMutableBufferPointer { synth.render(into: $0) }
        #expect(abs(buffer.last!) < 0.001)
        #expect(synth.isSilent)
    }
}

@Suite("Custom tunings")
struct CustomTuningTests {
    @Test func parsesNoteNames() {
        #expect(CustomTuning.parseNotes("D2 A2 D3 G3 A3 D4") == [38, 45, 50, 55, 57, 62])
        #expect(CustomTuning.parseNotes("c#4, Bb3 E♭2") == [61, 58, 39])
        #expect(CustomTuning.parseNotes("A4") == [69])
    }

    @Test func rejectsBadInput() {
        for bad in ["", "H2", "D", "D9", "D2 X3", String(repeating: "E2 ", count: 13)] {
            #expect(CustomTuning.parseNotes(bad) == nil, "\(bad)")
        }
    }

    @Test func roundTripsThroughText() {
        let tuning = CustomTuning(name: "DADGAD", strings: [38, 45, 50, 55, 57, 62], presetKey: "acousticGuitar")
        #expect(CustomTuning.parseNotes(tuning.notesText) == tuning.strings)
        #expect(tuning.asStringTuning.nearestString(to: 55.2) == 55)
    }
}
