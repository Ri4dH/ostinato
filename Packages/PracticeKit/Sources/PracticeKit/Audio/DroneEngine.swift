#if os(iOS)
import AVFoundation
import Foundation
import Observation
import Synchronization

/// State shared with the real-time render thread. Settings are handed over
/// through a mutex the render thread only *tries* to take, so it never blocks.
private final class DroneRenderState: @unchecked Sendable {
    var synth: DroneSynth   // touched only on the render thread
    let pending = Mutex<DroneSettings?>(nil)
    let fadeOutRequested = Atomic<Bool>(false)

    init(sampleRate: Double) { synth = DroneSynth(sampleRate: sampleRate) }
}

/// Sustained drone on any of the 12 notes, generated live with
/// `AVAudioSourceNode`. Fades in and out without clicks and mixes with the
/// metronome.
@MainActor
@Observable
public final class DroneEngine {
    public var settings: DroneSettings {
        didSet { if isPlaying, settings != oldValue { state.pending.withLock { $0 = settings } } }
    }

    public private(set) var isPlaying = false
    public private(set) var lastError: String?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let state: DroneRenderState
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    public init(settings: DroneSettings = DroneSettings()) {
        self.settings = settings
        let session = AVAudioSession.sharedInstance()
        let rate = session.sampleRate > 0 ? session.sampleRate : 48_000
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let state = DroneRenderState(sampleRate: rate)
        self.state = state

        let source = AVAudioSourceNode(format: format) { isSilence, _, frameCount, bufferList -> OSStatus in
            if let next = state.pending.withLockIfAvailable({ value -> DroneSettings? in
                defer { value = nil }
                return value
            }) ?? nil {
                state.synth.configure(next)
            }
            if state.fadeOutRequested.exchange(false, ordering: .relaxed) { state.synth.fadeOut() }
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first, let data = first.mData else { return noErr }
            let samples = UnsafeMutableBufferPointer(
                start: data.assumingMemoryBound(to: Float.self), count: Int(frameCount))
            state.synth.render(into: samples)
            for extra in buffers.dropFirst() {
                extra.mData?.copyMemory(from: data, byteCount: Int(first.mDataByteSize))
            }
            isSilence.pointee = ObjCBool(state.synth.isSilent)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    public func toggle() {
        if isPlaying { stop() } else { start() }
    }

    public func start() {
        stopTask?.cancel()
        do {
            try AudioSessionCoordinator.shared.acquire(.drone) { [weak self] in self?.stop() }
            state.pending.withLock { $0 = settings }
            if !engine.isRunning { try engine.start() }
            isPlaying = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            AudioSessionCoordinator.shared.release(.drone)
        }
    }

    /// Fades out, then stops the engine.
    public func stop() {
        guard isPlaying else { return }
        isPlaying = false
        state.fadeOutRequested.store(true, ordering: .relaxed)
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, !self.isPlaying else { return }
            self.engine.stop()
            AudioSessionCoordinator.shared.release(.drone)
        }
    }
}
#endif
