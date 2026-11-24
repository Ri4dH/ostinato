import Foundation
import SwiftData

/// Metadata for an audio recording. The audio itself lives on disk; see
/// `RecordingStorage` for how file URLs are built.
@Model
public final class Recording {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var duration: TimeInterval = 0
    /// File name only (`<uuid>.m4a`), never a path.
    public var audioFileName: String = ""
    public var fileLocationRaw: String = FileLocation.local.rawValue
    public var offsetInSession: TimeInterval?
    public var title: String = ""
    /// Cached audio analysis result (v1.2).
    public var analysisJSON: Data?
    /// Recordings made during a session are stored right away; the session
    /// itself is saved later. These IDs link them up in `SessionWriter`.
    public var sessionRefID: UUID?
    public var segmentRefID: UUID?

    public var session: PracticeSession?
    public var segment: SessionSegment?
    public var item: PracticeItem?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String,
        fileLocation: FileLocation = .local,
        offsetInSession: TimeInterval? = nil,
        title: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.fileLocationRaw = fileLocation.rawValue
        self.offsetInSession = offsetInSession
        self.title = title
    }

    public var fileLocation: FileLocation {
        get { FileLocation(rawValue: fileLocationRaw) ?? .local }
        set { fileLocationRaw = newValue.rawValue }
    }
}

/// One logged tempo for an item.
@Model
public final class TempoEntry {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var bpm: Int = 60
    public var sourceRaw: String = TempoSource.manual.rawValue
    public var item: PracticeItem?

    public init(id: UUID = UUID(), date: Date = Date(), bpm: Int, source: TempoSource) {
        self.id = id
        self.date = date
        self.bpm = bpm
        self.sourceRaw = source.rawValue
    }

    public var source: TempoSource {
        get { TempoSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
