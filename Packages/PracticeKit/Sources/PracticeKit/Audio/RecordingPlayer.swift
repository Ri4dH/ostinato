#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// Plays a recording with scrubbing and pitch-preserved speed (0.5×–1.0×)
/// via `AVAudioUnitTimePitch`.
@MainActor
@Observable
public final class RecordingPlayer {
    public private(set) var isPlaying = false
    public private(set) var duration: TimeInterval = 0
    public private(set) var loadedURL: URL?
    public var rate: Float = 1 { didSet { timePitch.rate = max(0.5, min(rate, 1)) } }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var seekFrame: AVAudioFramePosition = 0
    @ObservationIgnored private var generation = 0

    public init() {
        engine.attach(player)
        engine.attach(timePitch)
    }

    public func load(_ url: URL) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        self.file = file
        loadedURL = url
        duration = Double(file.length) / file.processingFormat.sampleRate
        seekFrame = 0
        engine.disconnectNodeOutput(player)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(player, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: file.processingFormat)
    }

    public var currentTime: TimeInterval {
        guard let file else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        guard isPlaying, let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return Double(seekFrame) / sampleRate
        }
        return min(duration, Double(seekFrame + playerTime.sampleTime) / sampleRate)
    }

    public func togglePlay() { isPlaying ? pause() : play() }

    public func play() {
        guard let file, !isPlaying else { return }
        do {
            try AudioSessionCoordinator.shared.acquire(.playback) { [weak self] in self?.pause() }
            if !engine.isRunning { try engine.start() }
            if seekFrame >= file.length { seekFrame = 0 }
            schedule(from: seekFrame)
            player.play()
            isPlaying = true
        } catch {
            AudioSessionCoordinator.shared.release(.playback)
        }
    }

    public func pause() {
        guard isPlaying, let file else { return }
        seekFrame = AVAudioFramePosition(currentTime * file.processingFormat.sampleRate)
        generation += 1
        player.stop()
        isPlaying = false
        AudioSessionCoordinator.shared.release(.playback)
    }

    public func seek(to time: TimeInterval) {
        guard let file else { return }
        let wasPlaying = isPlaying
        if wasPlaying { generation += 1; player.stop() }
        seekFrame = AVAudioFramePosition(max(0, min(time, duration)) * file.processingFormat.sampleRate)
        if wasPlaying {
            schedule(from: seekFrame)
            player.play()
        }
    }

    public func stop() {
        generation += 1
        player.stop()
        if engine.isRunning { engine.stop() }
        if isPlaying { AudioSessionCoordinator.shared.release(.playback) }
        isPlaying = false
        seekFrame = 0
    }

    private func schedule(from frame: AVAudioFramePosition) {
        guard let file else { return }
        let remaining = AVAudioFrameCount(max(0, file.length - frame))
        guard remaining > 0 else { return }
        let gen = generation
        player.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                self.isPlaying = false
                self.seekFrame = 0
                self.player.stop()
                AudioSessionCoordinator.shared.release(.playback)
            }
        }
    }
}
#endif
