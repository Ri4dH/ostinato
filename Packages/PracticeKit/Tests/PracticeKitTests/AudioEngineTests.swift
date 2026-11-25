#if os(iOS)
import AVFoundation
import Foundation
import Testing
@testable import PracticeKit

/// Engines are only built on iOS; these run in the simulator test pass.
@Suite("Audio engines")
@MainActor
struct AudioEngineTests {
    /// Regression: a self-assigning didSet on an @Observable property
    /// recursed until the stack overflowed when the Tuner screen opened.
    @Test func settingTunerReferencePitchDoesNotRecurse() {
        let tuner = TunerEngine()
        tuner.a4 = 415
        #expect(tuner.a4 == 415)
        tuner.a4 = 500   // out of range: stored, clamped when used
        #expect(tuner.a4 == 500)
        tuner.transposition = -2
        tuner.showConcertPitch = true
        #expect(!tuner.isRunning)
    }

    /// Regression: audio callbacks inherited main-actor isolation and Swift 6
    /// trapped when the audio thread called them. These run the real engines
    /// long enough for render and completion callbacks to fire.
    @Test func metronomeRunsAcrossBarBoundaries() async throws {
        let metronome = MetronomeEngine(settings: MetronomeSettings(bpm: 240, beatsPerBar: 2))
        metronome.start()
        #expect(metronome.isRunning)
        try await Task.sleep(for: .seconds(2))   // several bars complete
        metronome.settings.bpm = 200              // restart path
        try await Task.sleep(for: .seconds(1))
        metronome.stop()
        #expect(!metronome.isRunning)
    }

    @Test func droneRendersAndStops() async throws {
        let drone = DroneEngine()
        drone.start()
        #expect(drone.isPlaying)
        try await Task.sleep(for: .seconds(1))
        drone.settings.pitchClass = 7              // hand-off to the render thread
        try await Task.sleep(for: .seconds(0.5))
        drone.stop()
        try await Task.sleep(for: .seconds(0.6))
        #expect(!drone.isPlaying)
    }

    @Test func recordingPlaysToTheEnd() async throws {
        let url = tempDirectory().appending(path: "tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let count = AVAudioFrameCount(44_100 / 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        for i in 0..<Int(count) { buffer.floatChannelData![0][i] = Float(0.2 * sin(2 * .pi * 440 * Double(i) / 44_100)) }
        do { try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer) }

        let player = RecordingPlayer()
        try player.load(url)
        player.play()
        #expect(player.isPlaying)
        try await Task.sleep(for: .seconds(1.5))  // completion handler fires
        #expect(!player.isPlaying)
    }

    @Test func metronomeAndDroneSettingsCanChangeWhileStopped() {
        let metronome = MetronomeEngine()
        metronome.settings.bpm = 132
        metronome.settings.subdivision = .triplets
        #expect(metronome.settings.bpm == 132)
        let drone = DroneEngine()
        drone.settings.pitchClass = 2
        drone.settings.voicing = .rootFifth
        #expect(drone.settings.pitchClass == 2)
    }
}
#endif
