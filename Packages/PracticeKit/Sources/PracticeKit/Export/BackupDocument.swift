import Foundation

/// Full JSON backup of the journal. Recordings' audio files are not
/// embedded; the app can zip them alongside.
public struct BackupDocument: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var instruments: [InstrumentDTO]
    public var items: [ItemDTO]
    public var sessions: [SessionDTO]
    public var tempoEntries: [TempoDTO]
    public var recordings: [RecordingDTO]
    public var goal: GoalSettings?

    public struct InstrumentDTO: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var presetKey: String?
        public var symbolName: String
        public var colorHex: String
        public var transposition: Int
        public var sortIndex: Int
        public var isArchived: Bool
        public var createdAt: Date
    }

    public struct ItemDTO: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var composer: String?
        public var category: String
        public var status: String
        public var targetTempo: Int?
        public var lastTempo: Int?
        public var notes: String
        public var sortIndex: Int
        public var createdAt: Date
        public var updatedAt: Date
        public var instrumentID: UUID?
    }

    public struct SessionDTO: Codable, Sendable {
        public var id: UUID
        public var startDate: Date
        public var endDate: Date?
        public var activeDuration: TimeInterval
        public var source: String
        public var rating: Int?
        public var focus: Int?
        public var notes: String
        public var tags: [String]
        public var instrumentID: UUID?
        public var segments: [SegmentDTO]
        public var pauses: [PauseDTO]
    }

    public struct SegmentDTO: Codable, Sendable {
        public var id: UUID
        public var startDate: Date
        public var endDate: Date?
        public var activeDuration: TimeInterval
        public var label: String?
        public var sortIndex: Int
        public var itemID: UUID?
    }

    public struct PauseDTO: Codable, Sendable {
        public var id: UUID
        public var startDate: Date
        public var endDate: Date?
    }

    public struct TempoDTO: Codable, Sendable {
        public var id: UUID
        public var date: Date
        public var bpm: Int
        public var source: String
        public var itemID: UUID?
    }

    public struct RecordingDTO: Codable, Sendable {
        public var id: UUID
        public var createdAt: Date
        public var duration: TimeInterval
        public var audioFileName: String
        public var fileLocation: String
        public var offsetInSession: TimeInterval?
        public var title: String
        public var sessionID: UUID?
        public var segmentID: UUID?
        public var itemID: UUID?
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
