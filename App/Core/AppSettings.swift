import Foundation
import Observation
import PracticeKit

/// User preferences, stored in the App Group's UserDefaults so widgets and
/// intents see the same values.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.onboarded) } }
    var syncEnabled: Bool { didSet { defaults.set(syncEnabled, forKey: Key.sync) } }
    var syncRecordings: Bool { didSet { defaults.set(syncRecordings, forKey: Key.syncRecordings) } }
    var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.awake) } }
    var a4Reference: Double { didSet { defaults.set(a4Reference, forKey: Key.a4) } }
    var showConcertPitch: Bool { didSet { defaults.set(showConcertPitch, forKey: Key.concert) } }
    var reminderEnabled: Bool { didSet { defaults.set(reminderEnabled, forKey: Key.reminder) } }
    /// Minutes after midnight.
    var reminderMinutes: Int { didSet { defaults.set(reminderMinutes, forKey: Key.reminderTime) } }
    var lastInstrumentID: UUID? { didSet { defaults.set(lastInstrumentID?.uuidString, forKey: Key.lastInstrument) } }
    var goal: GoalSettings { didSet { save(goal, Key.goal) } }
    var metronome: MetronomeSettings { didSet { save(metronome, Key.metronome) } }
    var drone: DroneSettings { didSet { save(drone, Key.drone) } }
    /// Auto-delete recordings older than this many days; 0 = never.
    var recordingRetentionDays: Int { didSet { defaults.set(recordingRetentionDays, forKey: Key.retention) } }
    var customTunings: [CustomTuning] { didSet { save(customTunings, Key.tunings) } }
    /// Last known iCloud sign-in state. Checking it can block for seconds, so
    /// launch uses this and the real value is refreshed in the background.
    var iCloudSignedIn: Bool { didSet { defaults.set(iCloudSignedIn, forKey: Key.iCloud) } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.sync: true, Key.syncRecordings: true, Key.awake: true,
            Key.a4: NoteMath.defaultA4, Key.reminderTime: 18 * 60
        ])
        hasOnboarded = defaults.bool(forKey: Key.onboarded)
        syncEnabled = defaults.bool(forKey: Key.sync)
        syncRecordings = defaults.bool(forKey: Key.syncRecordings)
        keepScreenAwake = defaults.bool(forKey: Key.awake)
        a4Reference = NoteMath.a4Range.contains(defaults.double(forKey: Key.a4)) ? defaults.double(forKey: Key.a4) : NoteMath.defaultA4
        showConcertPitch = defaults.bool(forKey: Key.concert)
        reminderEnabled = defaults.bool(forKey: Key.reminder)
        reminderMinutes = defaults.integer(forKey: Key.reminderTime)
        lastInstrumentID = defaults.string(forKey: Key.lastInstrument).flatMap(UUID.init(uuidString:))
        goal = Self.load(GoalSettings.self, Key.goal, defaults) ?? .default
        metronome = Self.load(MetronomeSettings.self, Key.metronome, defaults) ?? MetronomeSettings()
        drone = Self.load(DroneSettings.self, Key.drone, defaults) ?? DroneSettings()
        recordingRetentionDays = defaults.integer(forKey: Key.retention)
        customTunings = Self.load([CustomTuning].self, Key.tunings, defaults) ?? []
        iCloudSignedIn = defaults.bool(forKey: Key.iCloud)
    }

    var reminderDateComponents: DateComponents {
        DateComponents(hour: reminderMinutes / 60, minute: reminderMinutes % 60)
    }

    func resetAll() {
        for key in Key.all { defaults.removeObject(forKey: key) }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private enum Key {
        static let onboarded = "hasOnboarded"
        static let sync = "syncEnabled"
        static let syncRecordings = "syncRecordings"
        static let awake = "keepScreenAwake"
        static let a4 = "a4Reference"
        static let concert = "showConcertPitch"
        static let reminder = "reminderEnabled"
        static let reminderTime = "reminderMinutes"
        static let lastInstrument = "lastInstrumentID"
        static let goal = "goal"
        static let metronome = "metronome"
        static let drone = "drone"
        static let retention = "recordingRetentionDays"
        static let tunings = "customTunings"
        static let iCloud = "iCloudSignedIn"
        static let all = [onboarded, sync, syncRecordings, awake, a4, concert, reminder, reminderTime,
                          lastInstrument, goal, metronome, drone, retention, tunings]
    }
}
