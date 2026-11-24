#if os(iOS)
import AVFoundation
import Foundation

/// The audio features that can be running at once.
public enum AudioUser: Hashable, Sendable {
    case metronome, drone, tuner, recorder, playback
}

/// One place that configures `AVAudioSession` and fans out interruptions.
/// Metronome, drone and recording mix together and keep playing in the
/// background (audio background mode).
@MainActor
public final class AudioSessionCoordinator {
    public static let shared = AudioSessionCoordinator()

    private var users: Set<AudioUser> = []
    private var interruptionHandlers: [AudioUser: @MainActor () -> Void] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                if raw == AVAudioSession.InterruptionType.began.rawValue {
                    AudioSessionCoordinator.shared.handleInterruptionBegan()
                }
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AudioSessionCoordinator.shared.handleInterruptionBegan() }
        })
    }

    /// Activates the session for a feature. `onInterruption` is called when a
    /// phone call, Siri or another app takes the audio; the feature must stop.
    public func acquire(_ user: AudioUser, onInterruption: @escaping @MainActor () -> Void) throws {
        interruptionHandlers[user] = onInterruption
        if users.isEmpty {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true)
        }
        users.insert(user)
    }

    public func release(_ user: AudioUser) {
        users.remove(user)
        interruptionHandlers[user] = nil
        if users.isEmpty {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public var isActive: Bool { !users.isEmpty }

    private func handleInterruptionBegan() {
        let handlers = interruptionHandlers
        for handler in handlers.values { handler() }
    }

    /// Asks for microphone access. Call only when the user starts a feature
    /// that needs it (never during onboarding).
    public static func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    public static var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }
}
#endif
