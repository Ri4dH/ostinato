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
