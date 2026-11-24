import Foundation

/// Groups shown in the instrument picker.
public enum InstrumentGroup: String, CaseIterable, Sendable, Identifiable {
    case keyboard, strings, guitar, woodwinds, brass, percussion, voice, other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .keyboard: String(localized: "Keyboard", bundle: .module)
        case .strings: String(localized: "Strings", bundle: .module)
        case .guitar: String(localized: "Guitar family", bundle: .module)
        case .woodwinds: String(localized: "Woodwinds", bundle: .module)
        case .brass: String(localized: "Brass", bundle: .module)
        case .percussion: String(localized: "Percussion", bundle: .module)
        case .voice: String(localized: "Voice", bundle: .module)
        case .other: String(localized: "Other", bundle: .module)
        }
    }
}

/// A built-in instrument the user can add with one tap. Users can edit name,
/// color and transposition after adding.
///
/// `symbolName` uses built-in SF Symbols as placeholders. Final art ships as
/// custom `.symbolset`s under the same names in the asset catalog, so swapping
/// requires no code change other than these strings.
public struct InstrumentPreset: Sendable, Identifiable, Hashable {
    public let key: String
    public let name: String
    public let group: InstrumentGroup
    public let symbolName: String
    public let colorHex: String
    public let transposition: Int
    /// False for drum kit, theory, ear training etc. Hides tuner and drone.
    public let hasPitch: Bool

    public var id: String { key }

    public static func preset(forKey key: String) -> InstrumentPreset? {
        all.first { $0.key == key }
    }

    public static func presets(in group: InstrumentGroup) -> [InstrumentPreset] {
        all.filter { $0.group == group }
    }

    private static func p(
        _ key: String, _ name: String, _ group: InstrumentGroup, _ symbol: String,
        _ color: Int, transposition: Int = 0, pitch: Bool = true
    ) -> InstrumentPreset {
        InstrumentPreset(
            key: key, name: name, group: group, symbolName: symbol,
            colorHex: InstrumentPalette.colors[color % InstrumentPalette.colors.count].hex,
            transposition: transposition, hasPitch: pitch
        )
    }

    private static func l(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: .module)
    }

    public static let all: [InstrumentPreset] = [
        // Keyboard
        p("piano", l("Piano"), .keyboard, "pianokeys", 0),
        p("keyboard", l("Keyboard/Synth"), .keyboard, "pianokeys.inverse", 1),
        p("organ", l("Organ"), .keyboard, "pianokeys.inverse", 2),
        p("harpsichord", l("Harpsichord"), .keyboard, "pianokeys", 3),
        p("accordion", l("Accordion"), .keyboard, "pianokeys", 4),
        // Strings
        p("violin", l("Violin"), .strings, "music.quarternote.3", 5),
        p("viola", l("Viola"), .strings, "music.quarternote.3", 6),
        p("cello", l("Cello"), .strings, "music.quarternote.3", 7),
        p("doubleBass", l("Double Bass"), .strings, "music.quarternote.3", 8),
        p("harp", l("Harp"), .strings, "music.quarternote.3", 9),
        // Guitar family
        p("acousticGuitar", l("Acoustic Guitar"), .guitar, "guitars", 3),
        p("classicalGuitar", l("Classical Guitar"), .guitar, "guitars", 4),
        p("electricGuitar", l("Electric Guitar"), .guitar, "guitars.fill", 0),
        p("bassGuitar", l("Bass Guitar"), .guitar, "guitars.fill", 8),
        p("ukulele", l("Ukulele"), .guitar, "guitars", 10),
        p("mandolin", l("Mandolin"), .guitar, "guitars", 11),
        p("banjo", l("Banjo"), .guitar, "guitars", 2),
        // Woodwinds
        p("flute", l("Flute"), .woodwinds, "wind", 5),
        p("piccolo", l("Piccolo"), .woodwinds, "wind", 6),
        p("recorder", l("Recorder"), .woodwinds, "wind", 7),
        p("oboe", l("Oboe"), .woodwinds, "wind", 9),
        p("bassoon", l("Bassoon"), .woodwinds, "wind", 3),
        p("clarinet", l("Clarinet in B♭"), .woodwinds, "wind", 1, transposition: -2),
        p("bassClarinet", l("Bass Clarinet"), .woodwinds, "wind", 8, transposition: -14),
        p("altoSax", l("Alto Sax"), .woodwinds, "wind", 4, transposition: -9),
        p("tenorSax", l("Tenor Sax"), .woodwinds, "wind", 2, transposition: -14),
        p("baritoneSax", l("Baritone Sax"), .woodwinds, "wind", 11, transposition: -21),
        p("sopranoSax", l("Soprano Sax"), .woodwinds, "wind", 10, transposition: -2),
        // Brass
        p("trumpet", l("Trumpet in B♭"), .brass, "horn", 4, transposition: -2),
        p("cornet", l("Cornet"), .brass, "horn", 3, transposition: -2),
        p("frenchHorn", l("French Horn in F"), .brass, "horn.blast", 2, transposition: -7),
        p("trombone", l("Trombone"), .brass, "horn", 11),
        p("euphonium", l("Euphonium"), .brass, "horn", 8),
        p("tuba", l("Tuba"), .brass, "horn.blast", 7),
        // Percussion
        p("drumKit", l("Drum Kit"), .percussion, "metronome", 0, pitch: false),
        p("snare", l("Snare"), .percussion, "metronome", 1, pitch: false),
        p("mallets", l("Mallets/Marimba"), .percussion, "metronome.fill", 5),
        p("timpani", l("Timpani"), .percussion, "metronome.fill", 6),
        p("handPercussion", l("Hand Percussion"), .percussion, "hand.raised", 9, pitch: false),
        // Voice
        p("voice", l("Voice / Singing"), .voice, "music.mic", 10),
        // Other
        p("theory", l("Music Theory"), .other, "book.closed", 6, pitch: false),
        p("earTraining", l("Ear Training"), .other, "ear", 7),
        p("composition", l("Composition"), .other, "music.note.list", 9, pitch: false),
        p("conducting", l("Conducting"), .other, "hand.wave", 11, pitch: false),
        p("other", l("Other"), .other, "music.note", 0)
    ]
}

/// Instrument colors. The first 8 are a validated categorical chart palette
/// (lightness band, chroma floor, colorblind separation, in fixed order) with
/// separate dark-mode steps, because instrument color is also chart color.
/// The last 4 are extra choices; charts still label every series.
public enum InstrumentPalette {
    public struct Swatch: Sendable, Identifiable, Hashable {
        public let hex: String
        public let darkHex: String
        public let name: String
        public var id: String { hex }
    }

    public static let colors: [Swatch] = [
        Swatch(hex: "#2A78D6", darkHex: "#3987E5", name: String(localized: "Blue", bundle: .module)),
        Swatch(hex: "#EB6834", darkHex: "#D95926", name: String(localized: "Orange", bundle: .module)),
        Swatch(hex: "#1BAF7A", darkHex: "#199E70", name: String(localized: "Aqua", bundle: .module)),
        Swatch(hex: "#EDA100", darkHex: "#C98500", name: String(localized: "Yellow", bundle: .module)),
        Swatch(hex: "#E87BA4", darkHex: "#D55181", name: String(localized: "Pink", bundle: .module)),
        Swatch(hex: "#008300", darkHex: "#0CA30C", name: String(localized: "Green", bundle: .module)),
        Swatch(hex: "#6250D6", darkHex: "#9085E9", name: String(localized: "Violet", bundle: .module)),
        Swatch(hex: "#E34948", darkHex: "#E66767", name: String(localized: "Red", bundle: .module)),
        Swatch(hex: "#1E8FA3", darkHex: "#2AA5BA", name: String(localized: "Teal", bundle: .module)),
        Swatch(hex: "#9A6B3A", darkHex: "#B88552", name: String(localized: "Brown", bundle: .module)),
        Swatch(hex: "#B347A8", darkHex: "#C866BE", name: String(localized: "Magenta", bundle: .module)),
        Swatch(hex: "#6B7280", darkHex: "#8E95A3", name: String(localized: "Graphite", bundle: .module))
    ]

    public static let defaultHex = "#2A78D6"

    /// The dark-mode step for a stored (light) hex; unknown colors pass through.
    public static func hex(_ stored: String, dark: Bool) -> String {
        guard dark, let swatch = colors.first(where: { $0.hex.caseInsensitiveCompare(stored) == .orderedSame }) else {
            return stored
        }
        return swatch.darkHex
    }

    /// Sequential single-hue ramp (blue, light → dark) for magnitude: heatmaps.
    public static let sequentialBlue = ["#CDE2FB", "#9EC5F4", "#6DA7EC", "#3987E5", "#256ABF", "#184F95", "#0D366B"]
}
