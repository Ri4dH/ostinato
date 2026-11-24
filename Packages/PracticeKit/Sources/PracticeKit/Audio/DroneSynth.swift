import Foundation

public enum DroneTimbre: String, Codable, CaseIterable, Sendable, Identifiable {
    case sine, organ, cello
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sine: String(localized: "Pure", bundle: .module)
        case .organ: String(localized: "Organ", bundle: .module)
        case .cello: String(localized: "Cello", bundle: .module)
        }
    }

    /// Harmonic amplitudes (1st harmonic first), normalized when rendering.
    var harmonics: [Float] {
        switch self {
        case .sine: [1]
        case .organ: [1, 0.5, 0.33, 0.25, 0, 0.12, 0, 0.08]
        case .cello: [1, 0.7, 0.55, 0.4, 0.3, 0.22, 0.15, 0.1, 0.07, 0.05]
        }
    }
}

public enum DroneVoicing: String, Codable, CaseIterable, Sendable, Identifiable {
    case root, rootFifth, rootFifthOctave
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .root: String(localized: "Root", bundle: .module)
        case .rootFifth: String(localized: "Root + 5th", bundle: .module)
        case .rootFifthOctave: String(localized: "Root + 5th + octave", bundle: .module)
        }
    }

    /// Semitone offsets from the root.
    public var intervals: [Int] {
        switch self {
        case .root: [0]
        case .rootFifth: [0, 7]
        case .rootFifthOctave: [0, 7, 12]
        }
    }
}

public struct DroneSettings: Codable, Sendable, Equatable {
    /// Pitch class 0 = C … 11 = B, as written for the instrument (or concert).
    public var pitchClass: Int
    public var octave: Int
    public var timbre: DroneTimbre
    public var voicing: DroneVoicing
    public var volume: Float
    public var a4: Double
    public var transposition: Int
    public var useConcertPitch: Bool

    public init(pitchClass: Int = 9, octave: Int = 3, timbre: DroneTimbre = .organ, voicing: DroneVoicing = .root,
                volume: Float = 0.5, a4: Double = NoteMath.defaultA4, transposition: Int = 0, useConcertPitch: Bool = false) {
        self.pitchClass = ((pitchClass % 12) + 12) % 12
        self.octave = max(1, min(octave, 6))
        self.timbre = timbre
        self.voicing = voicing
        self.volume = max(0, min(volume, 1))
        self.a4 = NoteMath.a4Range.clamp(a4)
        self.transposition = transposition
        self.useConcertPitch = useConcertPitch
    }

    /// Concert MIDI note of the root.
    public var rootConcertMidi: Int {
        let written = (octave + 1) * 12 + pitchClass
        return useConcertPitch ? written : written + transposition
    }

    /// Concert frequencies for each voice.
    public var frequencies: [Double] {
        voicing.intervals.map { NoteMath.frequency(midi: Double(rootConcertMidi + $0), a4: a4) }
    }
}

/// Additive oscillator bank with click-free gain ramps. Owned by the audio
/// render thread; never allocates while rendering.
public struct DroneSynth: Sendable {
    public let sampleRate: Double
    private var phases: [Double] = Array(repeating: 0, count: 3)
    private var frequencies: [Double] = [220]
    private var harmonics: [Float] = [1]
    private var harmonicNorm: Float = 1
    private var gain: Float = 0
    public private(set) var targetGain: Float = 0
    /// Per-sample smoothing coefficient (~40 ms time constant).
    private let rampCoefficient: Float

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.rampCoefficient = Float(1 - exp(-1 / (0.04 * sampleRate)))
    }

    public var currentGain: Float { gain }
    public var isSilent: Bool { gain < 0.0001 && targetGain == 0 }

    public mutating func configure(_ settings: DroneSettings) {
        frequencies = settings.frequencies
        harmonics = settings.timbre.harmonics
        harmonicNorm = 1 / max(1, harmonics.reduce(0, +))
        targetGain = settings.volume * 0.6 / Float(max(1, frequencies.count)).squareRoot()
    }

    public mutating func fadeOut() { targetGain = 0 }

    public mutating func render(into buffer: UnsafeMutableBufferPointer<Float>) {
        let voices = min(frequencies.count, phases.count)
        let twoPi = 2 * Double.pi
        for i in 0..<buffer.count {
            gain += (targetGain - gain) * rampCoefficient
            var sample: Float = 0
            if gain > 0.00001 {
                for v in 0..<voices {
                    let phase = phases[v]
                    for (h, amp) in harmonics.enumerated() where amp > 0 {
                        sample += amp * Float(sin(phase * Double(h + 1)))
                    }
                    phases[v] = (phase + twoPi * frequencies[v] / sampleRate).truncatingRemainder(dividingBy: twoPi)
                }
            }
            buffer[i] = sample * harmonicNorm * gain
        }
    }
}
