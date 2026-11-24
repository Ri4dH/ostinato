import Foundation

/// What kind of repertoire entry a `PracticeItem` is.
public enum ItemCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case piece, exercise, scale, technique, sightReading, improv, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .piece: String(localized: "Piece", bundle: .module)
        case .exercise: String(localized: "Exercise", bundle: .module)
        case .scale: String(localized: "Scales", bundle: .module)
        case .technique: String(localized: "Technique", bundle: .module)
        case .sightReading: String(localized: "Sight-reading", bundle: .module)
        case .improv: String(localized: "Improvisation", bundle: .module)
        case .other: String(localized: "Other", bundle: .module)
        }
    }

    public var symbolName: String {
        switch self {
        case .piece: "music.note.list"
        case .exercise: "figure.strengthtraining.traditional"
        case .scale: "stairs"
        case .technique: "hand.raised"
        case .sightReading: "eye"
        case .improv: "sparkles"
        case .other: "music.note"
        }
    }
}

/// Where a `PracticeItem` is in the learning process.
public enum ItemStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case learning, polishing, performanceReady, maintaining, archived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .learning: String(localized: "Learning", bundle: .module)
        case .polishing: String(localized: "Polishing", bundle: .module)
        case .performanceReady: String(localized: "Performance-ready", bundle: .module)
        case .maintaining: String(localized: "Maintaining", bundle: .module)
        case .archived: String(localized: "Archived", bundle: .module)
        }
    }

    /// Statuses shown in pickers and "active repertoire" lists.
    public static let active: [ItemStatus] = [.learning, .polishing, .performanceReady, .maintaining]
}

/// Which device or flow created a session.
public enum SessionSource: String, Codable, CaseIterable, Sendable {
    case phone, watch, manual, siri
}

/// Where a recording's audio file currently lives.
public enum FileLocation: String, Codable, CaseIterable, Sendable {
    case local, iCloud
}

/// How a tempo entry was captured.
public enum TempoSource: String, Codable, CaseIterable, Sendable {
    case manual, metronome, analysis
}
