import Foundation

/// Practice goal. Stored in the App Group's `UserDefaults` so widgets and the
/// watch can read it without opening the store.
public struct GoalSettings: Codable, Sendable, Equatable {
    public var dailyMinutes: Int
    public var daysPerWeek: Int
    /// When on, missed days within the weekly allowance (7 − daysPerWeek)
    /// don't break the streak.
    public var streakFreezeEnabled: Bool

    public init(dailyMinutes: Int = 30, daysPerWeek: Int = 5, streakFreezeEnabled: Bool = true) {
        self.dailyMinutes = max(1, min(dailyMinutes, 24 * 60))
        self.daysPerWeek = max(1, min(daysPerWeek, 7))
        self.streakFreezeEnabled = streakFreezeEnabled
    }

    public static let `default` = GoalSettings()

    public var dailySeconds: TimeInterval { TimeInterval(dailyMinutes * 60) }

    /// Days per week the user may skip without breaking the streak.
    public var restDaysPerWeek: Int { streakFreezeEnabled ? 7 - daysPerWeek : 0 }
}
