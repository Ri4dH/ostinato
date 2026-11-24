#if os(iOS)
import AVFoundation
import Foundation
import Observation

/// Collects mic samples on the tap thread and runs YIN with 50% overlap.
private final class PitchAnalyzer: @unchecked Sendable {
    private var buffer: [Float]
    private var filled = 0
    private let size: Int
    private let hop: Int
    private let detector: PitchDetector

    init(sampleRate: Double, size: Int = 4_096) {
        self.size = size
        self.hop = size / 2
        self.buffer = [Float](repeating: 0, count: size)
        self.detector = PitchDetector(sampleRate: sampleRate)
    }

    /// Returns estimates for each complete window (usually 0 or 1).
    func process(_ samples: UnsafeBufferPointer<Float>) -> [PitchEstimate?] {
        var results: [PitchEstimate?] = []
        var index = 0
        while index < samples.count {
            let count = min(size - filled, samples.count - index)
            for i in 0..<count { buffer[filled + i] = samples[index + i] }
            filled += count
            index += count
            if filled == size {
                results.append(buffer.withUnsafeBufferPointer { detector.detect($0) })
                // Keep the second half for overlap.
                for i in 0..<hop { buffer[i] = buffer[i + hop] }
                filled = hop
            }
        }
        return results
    }
}

/// Chromatic tuner. Audio is analyzed live and never stored.
@MainActor
@Observable
public final class TunerEngine {
    public var a4: Double = NoteMath.defaultA4 { didSet { a4 = NoteMath.a4Range.clamp(a4) } }
    public var transposition: Int = 0
    public var showConcertPitch = false

    public private(set) var reading: NoteReading?
    public private(set) var isRunning = false
    public private(set) var permissionDenied = false
    public private(set) var lastError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var smoother = PitchSmoother()
    @ObservationIgnored private var silentFrames = 0

    public init() {}

    public func start() async {
        guard !isRunning else { return }
        guard await AudioSessionCoordinator.requestMicrophoneAccess() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        do {
            try AudioSessionCoordinator.shared.acquire(.tuner) { [weak self] in self?.stop() }
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw TunerError.noInput }
            let analyzer = PitchAnalyzer(sampleRate: format.sampleRate)
            input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak self] buffer, _ in
                guard let channel = buffer.floatChannelData?[0] else { return }
                let estimates = analyzer.process(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                guard !estimates.isEmpty else { return }
                Task { @MainActor in
                    for estimate in estimates { self?.ingest(estimate) }
                }
            }
            try engine.start()
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            engine.inputNode.removeTap(onBus: 0)
            AudioSessionCoordinator.shared.release(.tuner)
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        reading = nil
        smoother.reset()
        AudioSessionCoordinator.shared.release(.tuner)
    }

    private func ingest(_ estimate: PitchEstimate?) {
        guard let estimate, estimate.clarity > 0.8 else {
            silentFrames += 1
            if silentFrames > 8 { reading = nil; smoother.reset() }
            return
        }
        silentFrames = 0
        let smoothed = smoother.add(estimate.frequency)
        reading = NoteMath.reading(frequency: smoothed, a4: a4, transposition: transposition)
    }

    enum TunerError: LocalizedError {
        case noInput
        var errorDescription: String? { String(localized: "No microphone is available.", bundle: .module) }
    }
}
#endif
