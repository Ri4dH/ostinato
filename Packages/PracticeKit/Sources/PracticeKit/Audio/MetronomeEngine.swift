#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// Sample-accurate metronome. Each bar is rendered into its own PCM buffer
/// at exact frame offsets (from `ClickScheduler`) and queued back-to-back on
/// an `AVAudioPlayerNode`, so clicks never depend on timers.
@MainActor
@Observable
public final class MetronomeEngine {
    public var settings: MetronomeSettings {
        didSet {
            guard settings != oldValue else { return }
            if isRunning, settings.bpm != oldValue.bpm || settings.beatsPerBar != oldValue.beatsPerBar
                || settings.subdivision != oldValue.subdivision || settings.beatUnit != oldValue.beatUnit
                || settings.accentFirstBeat != oldValue.accentFirstBeat {
                restart()
            }
            player.volume = settings.volume
        }
    }

    public private(set) var isRunning = false
    public var lastError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var format: AVAudioFormat
    @ObservationIgnored private var scheduler: ClickScheduler
    @ObservationIgnored private var nextBar: Int64 = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var clickSounds: [ClickKind: [Float]] = [:]
    private static let barsAhead = 3

    public init(settings: MetronomeSettings = MetronomeSettings()) {
        self.settings = settings
        let rate = AVAudioSession.sharedInstance().sampleRate > 0 ? AVAudioSession.sharedInstance().sampleRate : 48_000
        format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        scheduler = ClickScheduler(settings: settings, sampleRate: rate)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        clickSounds = Self.makeClickSounds(sampleRate: rate)
    }

    public func toggle() {
        if isRunning { stop() } else { start() }
    }

    public func start() {
        guard !isRunning else { return }
        do {
            try AudioSessionCoordinator.shared.acquire(.metronome) { [weak self] in self?.stop() }
            if !engine.isRunning { try engine.start() }
            isRunning = true
            lastError = nil
            beginScheduling()
        } catch {
            lastError = error.localizedDescription
            AudioSessionCoordinator.shared.release(.metronome)
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        generation += 1
        player.stop()
        engine.stop()
        AudioSessionCoordinator.shared.release(.metronome)
    }

    /// Beat index within the bar that is currently sounding (for the UI pulse).
    public func currentBeat() -> Int? {
        guard isRunning, let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime), playerTime.sampleTime >= 0 else { return nil }
        let framesPerBeat = scheduler.framesPerTick * Double(scheduler.ticksPerBeat)
        let beat = Int(Double(playerTime.sampleTime) / framesPerBeat)
        return beat % settings.beatsPerBar
    }

    // MARK: Scheduling

    private func restart() {
        generation += 1
        player.stop()
        beginScheduling()
    }

    private func beginScheduling() {
        scheduler = ClickScheduler(settings: settings, sampleRate: format.sampleRate)
        nextBar = 0
        player.volume = settings.volume
        for _ in 0..<Self.barsAhead { scheduleNextBar() }
        player.play()
    }

    private func scheduleNextBar() {
        let bar = nextBar
        nextBar += 1
        let length = AVAudioFrameCount(scheduler.barLength(bar))
        guard length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: length),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = length
        channel.update(repeating: 0, count: Int(length))
        for click in scheduler.clicks(inBar: bar) {
            guard let sound = clickSounds[click.kind] else { continue }
            let start = Int(click.frame)
            let count = min(sound.count, Int(length) - start)
            guard count > 0 else { continue }
            for i in 0..<count { channel[start + i] += sound[i] }
        }
        let gen = generation
        // Called on an audio thread: @Sendable keeps it off the main actor.
        player.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == gen else { return }
                self.scheduleNextBar()
            }
        }
    }

    /// Short decaying sine bursts. No audio files needed.
    private static func makeClickSounds(sampleRate: Double) -> [ClickKind: [Float]] {
        func click(_ frequency: Double, _ amplitude: Float, _ duration: Double) -> [Float] {
            let count = Int(sampleRate * duration)
            let attack = max(1, Int(sampleRate * 0.001))
            return (0..<count).map { i in
                let t = Double(i) / sampleRate
                let env = Float(min(1, Double(i) / Double(attack))) * Float(exp(-t * 90))
                return amplitude * env * Float(sin(2 * .pi * frequency * t))
            }
        }
        return [
            .accent: click(1_760, 0.9, 0.04),
            .beat: click(1_175, 0.7, 0.035),
            .subdivision: click(880, 0.35, 0.025)
        ]
    }
}
#endif
