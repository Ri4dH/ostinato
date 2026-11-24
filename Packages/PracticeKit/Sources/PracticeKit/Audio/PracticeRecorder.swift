#if os(iOS)
import AVFoundation
import Foundation
import Observation

public struct RecordingResult: Sendable, Equatable {
    public var fileName: String
    public var startedAt: Date
    public var duration: TimeInterval
    public var interrupted: Bool
}

/// Records AAC `.m4a`, mono, 64 kbps.
@MainActor
@Observable
public final class PracticeRecorder {
    public private(set) var isRecording = false
    public private(set) var startedAt: Date?
    public var permissionDenied = false
    public private(set) var lastError: String?
    /// Called when a recording ends, including when an interruption stopped it.
    @ObservationIgnored public var onFinish: (@MainActor (RecordingResult) -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var fileName: String?

    public init() {}

    public static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    public func start(storage: RecordingStorage) async {
        guard !isRecording else { return }
        guard await AudioSessionCoordinator.requestMicrophoneAccess() else {
            permissionDenied = true
            return
        }
        permissionDenied = false
        do {
            try storage.ensureDirectories()
            let name = RecordingStorage.newFileName()
            guard let url = storage.url(for: name, at: .local) else { return }
            try AudioSessionCoordinator.shared.acquire(.recorder) { [weak self] in self?.finish(interrupted: true) }
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw RecorderError.couldNotStart }
            self.recorder = recorder
            self.fileName = name
            startedAt = Date()
            isRecording = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            AudioSessionCoordinator.shared.release(.recorder)
        }
    }

    public func stop() { finish(interrupted: false) }

    /// 0…1 level for the meter. Call from a `TimelineView`.
    public func level() -> Float {
        guard let recorder, isRecording else { return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)
        return max(0, min(1, (db + 50) / 50))
    }

    public var elapsed: TimeInterval { recorder?.currentTime ?? 0 }

    private func finish(interrupted: Bool) {
        guard isRecording, let recorder, let fileName, let startedAt else { return }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.fileName = nil
        self.startedAt = nil
        isRecording = false
        AudioSessionCoordinator.shared.release(.recorder)
        onFinish?(RecordingResult(fileName: fileName, startedAt: startedAt, duration: duration, interrupted: interrupted))
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { String(localized: "Recording couldn't start.", bundle: .module) }
    }
}
#endif
