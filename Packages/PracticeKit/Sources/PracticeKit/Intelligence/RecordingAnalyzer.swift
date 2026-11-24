import Accelerate
import Foundation

/// How even the tempo was across a recording.
public enum TempoStability: String, Codable, Sendable {
    case steady, mostlySteady, drifting

    public var displayName: String {
        switch self {
        case .steady: String(localized: "steady", bundle: .module)
        case .mostlySteady: String(localized: "mostly steady", bundle: .module)
        case .drifting: String(localized: "drifting", bundle: .module)
        }
    }
}

public struct MusicalKey: Codable, Sendable, Hashable {
    /// Concert pitch class, 0 = C.
    public var tonic: Int
    public var isMinor: Bool

    public init(tonic: Int, isMinor: Bool) {
        self.tonic = ((tonic % 12) + 12) % 12
        self.isMinor = isMinor
    }

    public var name: String {
        let note = NoteMath.name(midi: tonic)
        return isMinor
            ? String(localized: "\(note) minor", bundle: .module)
            : String(localized: "\(note) major", bundle: .module)
    }
}

/// Result cached in `Recording.analysisJSON`. Only what the UI shows.
public struct RecordingAnalysis: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var bpm: Double?
    public var stability: TempoStability?
    public var key: MusicalKey?
    /// How strongly the audio matched the key profile, 0…1.
    public var keyConfidence: Double
    /// Average loudness in dBFS.
    public var loudness: Double
    public var peak: Double
    public var analyzedSeconds: Double

    public var roundedBPM: Int? { bpm.map { Int($0.rounded()) } }

    /// "≈ 96 BPM · D minor · tempo steady"
    public var summary: String {
        var parts: [String] = []
        if let bpm = roundedBPM { parts.append(String(localized: "≈ \(bpm) BPM", bundle: .module)) }
        if let key, keyConfidence >= 0.5 { parts.append(key.name) }
        if let stability { parts.append(String(localized: "tempo \(stability.displayName)", bundle: .module)) }
        return parts.isEmpty ? String(localized: "No clear tempo or key", bundle: .module) : parts.joined(separator: " · ")
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> RecordingAnalysis? {
        guard let data, let analysis = try? JSONDecoder().decode(RecordingAnalysis.self, from: data),
              analysis.version == currentVersion else { return nil }
        return analysis
    }
}

/// On-device tempo, key, stability and loudness analysis (spectral flux +
/// autocorrelation for tempo, chroma + Krumhansl–Schmuckler profiles for key).
/// Pure and synchronous; call from a background task.
public struct RecordingAnalyzer: Sendable {
    public var frameSize = 2_048
    public var hopSize = 512
    public var minBPM = 40.0
    public var maxBPM = 220.0
    /// Window length for local tempo estimates (stability).
    public var stabilityWindow: TimeInterval = 8

    public init() {}

    public func analyze(_ samples: [Float], sampleRate: Double) -> RecordingAnalysis {
        let seconds = Double(samples.count) / sampleRate
        let (loudness, peak) = levels(samples)
        guard samples.count > frameSize * 4, loudness > -60 else {
            return RecordingAnalysis(version: RecordingAnalysis.currentVersion, bpm: nil, stability: nil, key: nil,
                                     keyConfidence: 0, loudness: loudness, peak: peak, analyzedSeconds: seconds)
        }
        let spectra = Spectra(samples: samples, frameSize: frameSize, hopSize: hopSize)
        let frameRate = sampleRate / Double(hopSize)
        let flux = spectra.flux
        var bpm = tempo(flux, frameRate: frameRate)
        let locals = localTempos(flux, frameRate: frameRate,
                                 range: bpm.map { ($0 * 0.8)...($0 * 1.25) } ?? (minBPM...maxBPM))
        if bpm == nil, locals.count >= 2 {
            // No single clear beat (e.g. the player sped up): use the median.
            bpm = locals.sorted()[locals.count / 2]
        }
        let stability = stabilityOf(locals)
        let (key, confidence) = self.key(spectra.chroma(sampleRate: sampleRate))
        return RecordingAnalysis(version: RecordingAnalysis.currentVersion, bpm: bpm, stability: stability, key: key,
                                 keyConfidence: confidence, loudness: loudness, peak: peak, analyzedSeconds: seconds)
    }

    // MARK: Levels

    func levels(_ samples: [Float]) -> (rms: Double, peak: Double) {
        guard !samples.isEmpty else { return (-120, -120) }
        let rms = Double(vDSP.rootMeanSquare(samples))
        let peak = Double(vDSP.maximumMagnitude(samples))
        func db(_ v: Double) -> Double { v > 0 ? max(-120, 20 * log10(v)) : -120 }
        return (db(rms), db(peak))
    }

    // MARK: Tempo

    /// Global tempo from the autocorrelation of the onset envelope, with a
    /// gentle preference for 70–160 BPM to avoid half/double-tempo picks.
    func tempo(_ flux: [Float], frameRate: Double, range: ClosedRange<Double>? = nil) -> Double? {
        let range = range ?? minBPM...maxBPM
        let minLag = max(1, Int((60 * frameRate / range.upperBound).rounded(.down)))
        let maxLag = Int((60 * frameRate / range.lowerBound).rounded(.up))
        guard flux.count > maxLag * 2 else { return nil }
        let env = normalized(flux)
        var scores = [Double](repeating: 0, count: maxLag + 2)
        for lag in max(1, minLag - 1)...(maxLag + 1) {
            var sum: Float = 0
            env.withUnsafeBufferPointer { e in
                vDSP_dotpr(e.baseAddress!, 1, e.baseAddress! + lag, 1, &sum, vDSP_Length(env.count - lag))
            }
            scores[lag] = Double(sum) / Double(env.count - lag)
        }
        var best = -Double.infinity, bestLag = 0
        for lag in minLag...maxLag {
            let bpm = 60 * frameRate / Double(lag)
            // Log-Gaussian prior centred on 110 BPM, one octave wide.
            let prior = exp(-0.5 * pow(log2(bpm / 110), 2))
            // Reward lags whose multiples also line up (true beat period).
            let harmonic = lag * 2 <= maxLag + 1 ? 0.5 * scores[lag * 2] : 0
            let score = (scores[lag] + harmonic) * (0.5 + 0.5 * prior)
            if score > best { best = score; bestLag = lag }
        }
        guard bestLag > 0, scores[bestLag] > 0 else { return nil }
        var refined = Double(bestLag)
        let a = scores[bestLag - 1], b = scores[bestLag], c = scores[bestLag + 1]
        let denom = a - 2 * b + c
        if abs(denom) > 1e-12 { refined += max(-0.5, min(0.5, 0.5 * (a - c) / denom)) }
        let bpm = 60 * frameRate / refined
        return range.contains(bpm) ? bpm : nil
    }

    /// Tempo in overlapping windows across the recording.
    func localTempos(_ flux: [Float], frameRate: Double, range: ClosedRange<Double>) -> [Double] {
        let window = Int(stabilityWindow * frameRate)
        guard window > 0, flux.count >= window * 2 else { return [] }
        return stride(from: 0, through: flux.count - window, by: window / 2).compactMap { start in
            tempo(Array(flux[start..<(start + window)]), frameRate: frameRate, range: range)
        }
    }

    /// The spread of local tempos decides the label.
    func stabilityOf(_ local: [Double]) -> TempoStability? {
        guard local.count >= 2 else { return nil }
        let mean = local.reduce(0, +) / Double(local.count)
        let spread = (local.max()! - local.min()!) / mean
        if spread < 0.04 { return .steady }
        if spread < 0.1 { return .mostlySteady }
        return .drifting
    }

    // MARK: Key

    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    func key(_ chroma: [Double]) -> (MusicalKey?, Double) {
        guard chroma.count == 12, chroma.reduce(0, +) > 0 else { return (nil, 0) }
        var best: (MusicalKey, Double)?
        for tonic in 0..<12 {
            for minor in [false, true] {
                let profile = minor ? Self.minorProfile : Self.majorProfile
                let rotated = (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
                let r = correlation(chroma, rotated)
                if r > (best?.1 ?? -2) { best = (MusicalKey(tonic: tonic, isMinor: minor), r) }
            }
        }
        guard let best else { return (nil, 0) }
        return (best.0, max(0, min(1, best.1)))
    }

    private func correlation(_ x: [Double], _ y: [Double]) -> Double {
        let mx = x.reduce(0, +) / 12, my = y.reduce(0, +) / 12
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in 0..<12 {
            num += (x[i] - mx) * (y[i] - my)
            dx += (x[i] - mx) * (x[i] - mx)
            dy += (y[i] - my) * (y[i] - my)
        }
        return dx > 0 && dy > 0 ? num / (dx * dy).squareRoot() : 0
    }

    private func normalized(_ values: [Float]) -> [Float] {
        let mean = vDSP.mean(values)
        let centred = vDSP.add(-mean, values)
        let norm = max(Float.ulpOfOne, vDSP.rootMeanSquare(centred))
        return vDSP.divide(centred, norm)
    }
}

/// Magnitude spectra of overlapping Hann-windowed frames.
struct Spectra {
    let frameSize: Int
    /// Log-compressed magnitudes, `frameSize / 2` bins per frame.
    let frames: [[Float]]

    init(samples: [Float], frameSize: Int, hopSize: Int) {
        self.frameSize = frameSize
        let bins = frameSize / 2
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        guard let dft = try? vDSP.DiscreteFourierTransform(previous: nil, count: frameSize, direction: .forward,
                                                           transformType: .complexComplex, ofType: Float.self) else {
            frames = []
            return
        }
        let zeros = [Float](repeating: 0, count: frameSize)
        var result: [[Float]] = []
        result.reserveCapacity(samples.count / hopSize)
        var start = 0
        while start + frameSize <= samples.count {
            let frame = vDSP.multiply(samples[start..<(start + frameSize)], window)
            let (re, im) = dft.transform(real: frame, imaginary: zeros)
            var mags = [Float](repeating: 0, count: bins)
            for k in 0..<bins { mags[k] = log1p(100 * (re[k] * re[k] + im[k] * im[k]).squareRoot()) }
            result.append(mags)
            start += hopSize
        }
        frames = result
    }

    /// Positive spectral change per frame: the onset envelope.
    var flux: [Float] {
        guard frames.count > 1 else { return [] }
        var out = [Float](repeating: 0, count: frames.count)
        for i in 1..<frames.count {
            let diff = vDSP.subtract(frames[i], frames[i - 1])
            out[i] = vDSP.sum(vDSP.clip(diff, to: 0...Float.greatestFiniteMagnitude))
        }
        return out
    }

    /// Energy per pitch class from 55 Hz to 2 kHz.
    func chroma(sampleRate: Double) -> [Double] {
        var chroma = [Double](repeating: 0, count: 12)
        let binHz = sampleRate / Double(frameSize)
        let mapping: [(Int, Int)] = (1..<(frameSize / 2)).compactMap { k in
            let f = Double(k) * binHz
            guard f >= 55, f <= 2_000 else { return nil }
            return (k, Int(NoteMath.midi(frequency: f).rounded()) % 12)
        }
        for frame in frames {
            for (k, pc) in mapping { chroma[pc] += Double(frame[k] * frame[k]) }
        }
        return chroma
    }
}
