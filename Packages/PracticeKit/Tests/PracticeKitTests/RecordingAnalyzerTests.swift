import AVFoundation
import Foundation
import Testing
@testable import PracticeKit

/// Synthetic signals for analysis tests.
private enum Synth {
    static let rate = 22_050.0

    /// Plucked-ish notes (decaying harmonics) at beat times.
    static func notes(_ events: [(time: Double, midis: [Int], length: Double)], duration: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int(duration * rate))
        for event in events {
            let start = Int(event.time * rate)
            let count = min(Int(event.length * rate), out.count - start)
            guard count > 0 else { continue }
            for midi in event.midis {
                let f = NoteMath.frequency(midi: Double(midi))
                for i in 0..<count {
                    let t = Double(i) / rate
                    let env = exp(-t * 3) * min(1, t * 400)
                    let v = sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t) + 0.25 * sin(6 * .pi * f * t)
                    out[start + i] += Float(0.15 * env * v)
                }
            }
        }
        return out
    }

    /// One note per beat; tempo may change linearly from `bpm` to `endBPM`.
    static func beats(bpm: Double, endBPM: Double? = nil, duration: Double, midi: Int = 62) -> [Float] {
        var events: [(Double, [Int], Double)] = []
        var t = 0.0
        while t < duration {
            let progress = t / duration
            let current = bpm + ((endBPM ?? bpm) - bpm) * progress
            events.append((t, [midi], 0.25))
            t += 60 / current
        }
        return notes(events.map { (time: $0.0, midis: $0.1, length: $0.2) }, duration: duration)
    }

    static func progression(_ chords: [[Int]], bpm: Double, bars: Int) -> [Float] {
        let beat = 60 / bpm
        var events: [(time: Double, midis: [Int], length: Double)] = []
        for bar in 0..<bars {
            let chord = chords[bar % chords.count]
            for b in 0..<4 { events.append((Double(bar * 4 + b) * beat, chord, beat * 0.9)) }
        }
        return notes(events, duration: Double(bars * 4) * beat + 0.5)
    }
}

@Suite("Recording analysis")
struct RecordingAnalyzerTests {
    let analyzer = RecordingAnalyzer()

    @Test(arguments: [72.0, 96.0, 128.0, 150.0])
    func detectsSteadyTempo(bpm: Double) throws {
        let result = analyzer.analyze(Synth.beats(bpm: bpm, duration: 30), sampleRate: Synth.rate)
        let detected = try #require(result.bpm)
        #expect(abs(detected - bpm) < 2, "expected \(bpm), got \(detected)")
        #expect(result.stability == .steady)
    }

    @Test func flagsDriftingTempo() {
        let result = analyzer.analyze(Synth.beats(bpm: 84, endBPM: 116, duration: 40), sampleRate: Synth.rate)
        #expect(result.stability == .drifting || result.stability == .mostlySteady)
        #expect(result.stability != .steady)
    }

    @Test func detectsMinorKey() throws {
        // i – iv – V – i in D minor (the C♯ separates it from F major).
        let dm = [50, 62, 65, 69], gm = [55, 62, 67, 70], a = [57, 61, 64, 69]
        let result = analyzer.analyze(Synth.progression([dm, gm, a, dm], bpm: 90, bars: 8), sampleRate: Synth.rate)
        let key = try #require(result.key)
        #expect(key == MusicalKey(tonic: 2, isMinor: true), "got \(key.name)")
        #expect(result.summary.contains("D minor"))
    }

    @Test func detectsMajorKey() throws {
        let c = [48, 60, 64, 67], f = [53, 60, 65, 69], g = [55, 59, 62, 67]
        let result = analyzer.analyze(Synth.progression([c, f, g, c], bpm: 100, bars: 8), sampleRate: Synth.rate)
        #expect(result.key == MusicalKey(tonic: 0, isMinor: false))
    }

    @Test func silenceHasNoTempoOrKey() {
        let result = analyzer.analyze([Float](repeating: 0, count: 22_050 * 10), sampleRate: Synth.rate)
        #expect(result.bpm == nil)
        #expect(result.key == nil)
        #expect(result.summary == "No clear tempo or key")
    }

    @Test func loudnessIsInDBFS() {
        let tone = (0..<22_050).map { Float(0.5 * sin(2 * .pi * 440 * Double($0) / Synth.rate)) }
        let (rms, peak) = analyzer.levels(tone)
        #expect(abs(peak - (-6.02)) < 0.1)
        #expect(abs(rms - (-9.03)) < 0.1)
    }

    @Test func roundTripsThroughJSONAndRejectsOldVersions() throws {
        let result = analyzer.analyze(Synth.beats(bpm: 96, duration: 20), sampleRate: Synth.rate)
        #expect(RecordingAnalysis.decode(result.encoded()) == result)
        var old = result
        old.version = 0
        #expect(RecordingAnalysis.decode(old.encoded()) == nil)
    }

    @Test func decodesAndAnalyzesAFile() async throws {
        let url = tempDirectory().appending(path: "click.caf")
        let samples = Synth.beats(bpm: 110, duration: 20)
        let format = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let result = try await AudioFileDecoder.analyze(url: url)
        #expect(abs((result.bpm ?? 0) - 110) < 2)
        #expect(abs(result.analyzedSeconds - 20) < 0.1)
    }

    @Test func longRecordingAnalyzesQuickly() {
        let samples = Synth.beats(bpm: 100, duration: 180)
        let elapsed = ContinuousClock().measure { _ = analyzer.analyze(samples, sampleRate: Synth.rate) }
        #expect(elapsed < .seconds(10))
    }
}
