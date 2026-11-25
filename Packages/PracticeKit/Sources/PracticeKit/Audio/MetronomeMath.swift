import Foundation

public enum Subdivision: Int, Codable, CaseIterable, Sendable, Identifiable {
    case none = 1, eighths = 2, triplets = 3, sixteenths = 4
    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .none: String(localized: "None", bundle: .module)
        case .eighths: String(localized: "Eighths", bundle: .module)
        case .triplets: String(localized: "Triplets", bundle: .module)
        case .sixteenths: String(localized: "Sixteenths", bundle: .module)
        }
    }
}

public struct MetronomeSettings: Codable, Sendable, Equatable {
    public static let bpmRange: ClosedRange<Int> = 20...300

    public var bpm: Int { didSet { bpm = Self.bpmRange.clamp(bpm) } }
    public var beatsPerBar: Int { didSet { beatsPerBar = max(1, min(beatsPerBar, 16)) } }
    /// 4 = quarter-note beats, 8 = eighth-note beats.
    public var beatUnit: Int
    public var accentFirstBeat: Bool
    public var subdivision: Subdivision
    public var volume: Float

    public init(bpm: Int = 80, beatsPerBar: Int = 4, beatUnit: Int = 4, accentFirstBeat: Bool = true,
                subdivision: Subdivision = .none, volume: Float = 0.8) {
        self.bpm = Self.bpmRange.clamp(bpm)
        self.beatsPerBar = max(1, min(beatsPerBar, 16))
        self.beatUnit = beatUnit == 8 ? 8 : 4
        self.accentFirstBeat = accentFirstBeat
        self.subdivision = subdivision
        self.volume = max(0, min(volume, 1))
    }

    /// Common time signatures offered in the picker; any custom value works.
    public static let commonSignatures: [(Int, Int)] = [(2, 4), (3, 4), (4, 4), (5, 4), (6, 8), (7, 8), (9, 8), (12, 8)]

    /// 6/8, 9/8, 12/8: eighths grouped in threes.
    public var isCompound: Bool { beatUnit == 8 && beatsPerBar % 3 == 0 && beatsPerBar > 3 }
}

public enum ClickKind: Sendable, Equatable {
    case accent, beat, subdivision
}

public struct ScheduledClick: Sendable, Equatable {
    public var frame: Int64
    public var kind: ClickKind
}

/// Computes exact sample positions for clicks. Each position is derived from
/// the tick index (never accumulated), so there is no drift over time.
public struct ClickScheduler: Sendable {
    public let settings: MetronomeSettings
    public let sampleRate: Double

    public init(settings: MetronomeSettings, sampleRate: Double) {
        self.settings = settings
        self.sampleRate = sampleRate
    }

    public var ticksPerBeat: Int { settings.subdivision.rawValue }
    public var ticksPerBar: Int { settings.beatsPerBar * ticksPerBeat }
    public var framesPerTick: Double { sampleRate * 60 / Double(settings.bpm) / Double(ticksPerBeat) }

    public func frame(ofTick tick: Int64) -> Int64 { Int64((Double(tick) * framesPerTick).rounded()) }

    public func frame(ofBar bar: Int64) -> Int64 { frame(ofTick: bar * Int64(ticksPerBar)) }

    public func kind(ofTick tick: Int64) -> ClickKind {
        let inBar = Int(tick % Int64(ticksPerBar))
        if inBar % ticksPerBeat != 0 { return .subdivision }
        let beat = inBar / ticksPerBeat
        if beat == 0 { return settings.accentFirstBeat ? .accent : .beat }
        if settings.isCompound { return beat % 3 == 0 ? .beat : .subdivision }
        return .beat
    }

    /// Clicks in one bar, with frames relative to the bar's start.
    public func clicks(inBar bar: Int64) -> [ScheduledClick] {
        let barStart = frame(ofBar: bar)
        let first = bar * Int64(ticksPerBar)
        return (0..<Int64(ticksPerBar)).map { i in
            ScheduledClick(frame: frame(ofTick: first + i) - barStart, kind: kind(ofTick: first + i))
        }
    }

    public func barLength(_ bar: Int64) -> Int64 { frame(ofBar: bar + 1) - frame(ofBar: bar) }
}

/// Tap tempo: averages recent intervals, resets after a long gap.
public struct TapTempo: Sendable {
    private var taps: [TimeInterval] = []
    public var resetAfter: TimeInterval = 2
    public var maxTaps = 6

    public init() {}

    /// Registers a tap (seconds, any monotonic clock) and returns the BPM
    /// once two taps exist.
    public mutating func tap(at time: TimeInterval) -> Int? {
        if let last = taps.last, time - last > resetAfter || time <= last { taps.removeAll() }
        taps.append(time)
        if taps.count > maxTaps { taps.removeFirst(taps.count - maxTaps) }
        guard taps.count >= 2, let first = taps.first, let last = taps.last else { return nil }
        let interval = (last - first) / Double(taps.count - 1)
        guard interval > 0 else { return nil }
        return MetronomeSettings.bpmRange.clamp(Int((60 / interval).rounded()))
    }
}

extension ClosedRange where Bound: Comparable {
    public func clamp(_ value: Bound) -> Bound { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
