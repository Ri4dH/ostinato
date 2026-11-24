import Foundation

/// Duration formatting using system formatters (never hand-built strings),
/// so every language gets correct units and plurals.
public enum DurationText {
    /// "1h 20m" / "45m". For compact labels and charts.
    public static func short(_ seconds: TimeInterval) -> String {
        let duration = Duration.seconds(max(0, seconds.rounded()))
        if seconds < 60 {
            return duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
        }
        return duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    /// "1 hour, 20 minutes". For summaries and VoiceOver.
    public static func spoken(_ seconds: TimeInterval) -> String {
        let duration = Duration.seconds(max(0, seconds.rounded()))
        if seconds < 60 {
            return duration.formatted(.units(allowed: [.seconds], width: .wide))
        }
        return duration.formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
    }

    /// "12 minutes, 30 seconds". VoiceOver value for running timers.
    public static func timerSpoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds.rounded(.down)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "12:30" / "1:02:03". Monospaced timer digits when a static string is needed.
    public static func clock(_ seconds: TimeInterval) -> String {
        let duration = Duration.seconds(max(0, seconds.rounded(.down)))
        return seconds >= 3600
            ? duration.formatted(.time(pattern: .hourMinuteSecond))
            : duration.formatted(.time(pattern: .minuteSecond))
    }

    /// Whole minutes, for goal math and widgets.
    public static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded(.down)) }
}
