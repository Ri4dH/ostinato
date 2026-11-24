import Foundation

/// A pitch reading for the tuner.
public struct NoteReading: Sendable, Equatable {
    /// MIDI note number at concert pitch.
    public var concertMidi: Int
    /// MIDI note number as written for the instrument (concert − transposition).
    public var writtenMidi: Int
    /// Deviation from the nearest note, −50…+50 cents.
    public var cents: Double
    public var frequency: Double

    public func name(written: Bool) -> String { NoteMath.name(midi: written ? writtenMidi : concertMidi) }
    public func octave(written: Bool) -> Int { NoteMath.octave(midi: written ? writtenMidi : concertMidi) }
}

public enum NoteMath {
    public static let a4Range: ClosedRange<Double> = 415...466
    public static let defaultA4: Double = 440

    /// Pitch-class names. Flats for the black keys musicians usually read
    /// that way (E♭, A♭, B♭), sharps for C♯ and F♯.
    public static let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]

    public static func frequency(midi: Double, a4: Double = defaultA4) -> Double {
        a4 * pow(2, (midi - 69) / 12)
    }

    public static func midi(frequency: Double, a4: Double = defaultA4) -> Double {
        69 + 12 * log2(frequency / a4)
    }

    public static func cents(from reference: Double, to frequency: Double) -> Double {
        1200 * log2(frequency / reference)
    }

    public static func name(midi: Int) -> String { names[((midi % 12) + 12) % 12] }

    /// Scientific pitch notation: middle C (MIDI 60) is C4.
    public static func octave(midi: Int) -> Int { Int((Double(midi) / 12).rounded(.down)) - 1 }

    /// Nearest note for a frequency, honoring A4 and instrument transposition.
    /// A B♭ clarinet (transposition −2) playing concert B♭ reads as written C.
    public static func reading(frequency: Double, a4: Double = defaultA4, transposition: Int = 0) -> NoteReading? {
        guard frequency.isFinite, frequency > 0 else { return nil }
        let exact = midi(frequency: frequency, a4: a4)
        let nearest = Int(exact.rounded())
        let cents = (exact - Double(nearest)) * 100
        return NoteReading(concertMidi: nearest, writtenMidi: nearest - transposition, cents: cents, frequency: frequency)
    }

    /// Concert frequency for a written note on a transposing instrument.
    public static func concertFrequency(writtenMidi: Int, transposition: Int, a4: Double = defaultA4) -> Double {
        frequency(midi: Double(writtenMidi + transposition), a4: a4)
    }
}

/// Standard tunings for the tuner's string-by-string mode.
public struct StringTuning: Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// Concert-pitch MIDI notes, lowest string first.
    public let strings: [Int]

    public init(id: String, name: String, strings: [Int]) {
        self.id = id
        self.name = name
        self.strings = strings
    }

    public static func tunings(forPreset key: String?) -> [StringTuning] {
        switch key {
        case "violin": [StringTuning(id: "violin", name: "G D A E", strings: [55, 62, 69, 76])]
        case "viola": [StringTuning(id: "viola", name: "C G D A", strings: [48, 55, 62, 69])]
        case "cello": [StringTuning(id: "cello", name: "C G D A", strings: [36, 43, 50, 57])]
        case "doubleBass", "bassGuitar": [StringTuning(id: "bass", name: "E A D G", strings: [28, 33, 38, 43])]
        case "acousticGuitar", "classicalGuitar", "electricGuitar":
            [StringTuning(id: "guitar", name: "E A D G B E", strings: [40, 45, 50, 55, 59, 64]),
             StringTuning(id: "dropD", name: "Drop D", strings: [38, 45, 50, 55, 59, 64])]
        case "ukulele": [StringTuning(id: "ukulele", name: "G C E A", strings: [67, 60, 64, 69])]
        case "mandolin": [StringTuning(id: "mandolin", name: "G D A E", strings: [55, 62, 69, 76])]
        case "banjo": [StringTuning(id: "banjo", name: "Open G", strings: [67, 50, 55, 59, 62])]
        default: []
        }
    }

    /// The string closest to a reading.
    public func nearestString(to midi: Double) -> Int? {
        strings.min { abs(Double($0) - midi) < abs(Double($1) - midi) }
    }
}

/// A tuning the user defined (e.g. DADGAD), saved per instrument preset.
public struct CustomTuning: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Concert-pitch MIDI notes, lowest string first.
    public var strings: [Int]
    /// Preset the tuning belongs to (nil = all instruments).
    public var presetKey: String?

    public init(id: UUID = UUID(), name: String, strings: [Int], presetKey: String?) {
        self.id = id
        self.name = name
        self.strings = strings
        self.presetKey = presetKey
    }

    public var asStringTuning: StringTuning {
        StringTuning(id: id.uuidString, name: name, strings: strings)
    }

    /// "D2 A2 D3 G3 A3 D4" for display and editing.
    public var notesText: String {
        strings.map { "\(NoteMath.name(midi: $0))\(NoteMath.octave(midi: $0))" }.joined(separator: " ")
    }

    /// Parses notes like "D2 A2 D3 G3 A3 D4", "C#4", "Bb3" or "E♭2".
    /// Returns nil unless there are 1–12 valid notes between C0 and C8.
    public static func parseNotes(_ text: String) -> [Int]? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }).map(String.init)
        guard (1...12).contains(tokens.count) else { return nil }
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var notes: [Int] = []
        for token in tokens {
            var chars = Array(token)
            guard let first = chars.first, let base = letters[Character(first.uppercased())] else { return nil }
            chars.removeFirst()
            var offset = 0
            if let accidental = chars.first, "#♯b♭".contains(accidental) {
                offset = "#♯".contains(accidental) ? 1 : -1
                chars.removeFirst()
            }
            guard let octave = Int(String(chars)), (0...8).contains(octave) else { return nil }
            let midi = (octave + 1) * 12 + base + offset
            guard (12...108).contains(midi) else { return nil }
            notes.append(midi)
        }
        return notes
    }
}
