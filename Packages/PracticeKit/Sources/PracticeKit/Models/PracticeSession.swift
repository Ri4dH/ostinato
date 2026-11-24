import Foundation
import SwiftData

/// A completed (or manually logged) practice session.
///
/// The in-progress session lives in `ActiveSession` (a Codable snapshot in
/// the App Group) and is written here only when the user saves it. That keeps
/// widgets, the Live Activity, intents and the watch reading one small file
/// instead of the whole store.
@Model
public final class PracticeSession {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date?
    /// Total minus pauses, stored on finish.
    public var activeDuration: TimeInterval = 0
    public var sourceRaw: String = SessionSource.phone.rawValue
    public var rating: Int?
    public var focus: Int?
    public var notes: String = ""
    public var tags: [String] = []

    public var instrument: Instrument?

    @Relationship(deleteRule: .cascade, inverse: \SessionSegment.session)
    public var segments: [SessionSegment]? = []

    @Relationship(deleteRule: .cascade, inverse: \PauseInterval.session)
    public var pauses: [PauseInterval]? = []

    @Relationship(deleteRule: .nullify, inverse: \Recording.session)
    public var recordings: [Recording]? = []

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        activeDuration: TimeInterval = 0,
        source: SessionSource = .phone,
        instrument: Instrument? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activeDuration = activeDuration
        self.sourceRaw = source.rawValue
        self.instrument = instrument
    }

    public var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .phone }
        set { sourceRaw = newValue.rawValue }
    }

    public var sortedSegments: [SessionSegment] {
        (segments ?? []).sorted { ($0.sortIndex, $0.startDate) < ($1.sortIndex, $1.startDate) }
    }

    /// Recomputes `activeDuration` from segments. Call after editing segments.
    public func recomputeDuration() {
        activeDuration = (segments ?? []).reduce(0) { $0 + $1.activeDuration }
    }
}

/// One stretch of a session spent on one item (the "time per piece" feature).
@Model
public final class SessionSegment {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date?
    /// Excludes pauses that overlap this segment.
    public var activeDuration: TimeInterval = 0
    /// Used when no item is selected ("Warm-up").
    public var label: String?
    public var sortIndex: Int = 0

    public var session: PracticeSession?
    public var item: PracticeItem?

    @Relationship(deleteRule: .nullify, inverse: \Recording.segment)
    public var recordings: [Recording]? = []

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        activeDuration: TimeInterval = 0,
        label: String? = nil,
        sortIndex: Int = 0,
        item: PracticeItem? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.activeDuration = activeDuration
        self.label = label
        self.sortIndex = sortIndex
        self.item = item
    }

    /// Item title, else the free-text label, else a generic name.
    public var displayTitle: String {
        item?.title ?? label ?? String(localized: "General practice", bundle: .module)
    }
}

/// A pause inside a session.
@Model
public final class PauseInterval {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date?
    public var session: PracticeSession?

    public init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
    }
}
