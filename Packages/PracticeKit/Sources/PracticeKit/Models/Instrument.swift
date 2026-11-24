import Foundation
import SwiftData

/// An instrument (or discipline, like ear training) the musician practices.
///
/// CloudKit rules: every property has a default or is optional, no unique
/// attributes, all relationships optional with explicit inverses.
@Model
public final class Instrument {
    public var id: UUID = UUID()
    public var name: String = ""
    public var presetKey: String?
    public var symbolName: String = "music.note"
    public var colorHex: String = InstrumentPalette.defaultHex
    /// Semitones from concert pitch (B♭ clarinet = −2). Used by tuner and drone.
    public var transposition: Int = 0
    public var sortIndex: Int = 0
    public var isArchived: Bool = false
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \PracticeItem.instrument)
    public var items: [PracticeItem]? = []

    @Relationship(deleteRule: .nullify, inverse: \PracticeSession.instrument)
    public var sessions: [PracticeSession]? = []

    public init(
        id: UUID = UUID(),
        name: String,
        presetKey: String? = nil,
        symbolName: String = "music.note",
        colorHex: String = InstrumentPalette.defaultHex,
        transposition: Int = 0,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.presetKey = presetKey
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.transposition = transposition
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    public convenience init(preset: InstrumentPreset, sortIndex: Int = 0) {
        self.init(
            name: preset.name,
            presetKey: preset.key,
            symbolName: preset.symbolName,
            colorHex: preset.colorHex,
            transposition: preset.transposition,
            sortIndex: sortIndex
        )
    }

    /// Whether tuner and drone make sense for this instrument.
    public var hasPitch: Bool {
        guard let presetKey, let preset = InstrumentPreset.preset(forKey: presetKey) else { return true }
        return preset.hasPitch
    }
}
