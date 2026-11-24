import Foundation

public struct PitchEstimate: Sendable, Equatable {
    public var frequency: Double
    /// 0…1. Higher means a clearer, more periodic signal.
    public var clarity: Double
}

/// YIN pitch detection (de Cheveigné & Kawahara, 2002) with parabolic
/// interpolation. Pure and allocation-light; run it off the main thread.
public struct PitchDetector: Sendable {
    public var sampleRate: Double
    public var threshold: Double
    public var minFrequency: Double
    public var maxFrequency: Double
    /// Below this RMS level the input is treated as silence.
    public var silenceRMS: Float

    public init(sampleRate: Double, threshold: Double = 0.12, minFrequency: Double = 27.5,
                maxFrequency: Double = 2_100, silenceRMS: Float = 0.006) {
        self.sampleRate = sampleRate
        self.threshold = threshold
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
        self.silenceRMS = silenceRMS
    }

    /// Analyzes a buffer. It needs at least two periods of the lowest
    /// frequency (≈ 3,500 samples at 48 kHz for 27.5 Hz).
    public func detect(_ samples: [Float]) -> PitchEstimate? {
        samples.withUnsafeBufferPointer { detect($0) }
    }

    public func detect(_ x: UnsafeBufferPointer<Float>) -> PitchEstimate? {
        let n = x.count
        guard n >= 64 else { return nil }
        var energy: Float = 0
        for v in x { energy += v * v }
        guard (energy / Float(n)).squareRoot() >= silenceRMS else { return nil }

        let window = n / 2
        let minTau = max(2, Int(sampleRate / maxFrequency))
        let maxTau = min(window - 1, Int(sampleRate / minFrequency))
        guard maxTau > minTau + 2 else { return nil }

        // Difference function d(τ) and cumulative mean normalized d'(τ).
        var d = [Double](repeating: 0, count: maxTau + 1)
        d.withUnsafeMutableBufferPointer { d in
            for tau in 1...maxTau {
                var sum: Float = 0
                for j in 0..<window {
                    let delta = x[j] - x[j + tau]
                    sum += delta * delta
                }
                d[tau] = Double(sum)
            }
            d[0] = 1
            var running = 0.0
            for tau in 1...maxTau {
                running += d[tau]
                d[tau] = running > 0 ? d[tau] * Double(tau) / running : 1
            }
        }

        // First dip below the threshold, then walk to its local minimum.
        var tau = minTau
        var found: Int?
        while tau <= maxTau {
            if d[tau] < threshold {
                while tau + 1 <= maxTau, d[tau + 1] < d[tau] { tau += 1 }
                found = tau
                break
            }
            tau += 1
        }
        if found == nil {
            // No clear dip: use the global minimum if it's reasonably periodic.
            guard let best = (minTau...maxTau).min(by: { d[$0] < d[$1] }), d[best] < 0.35 else { return nil }
            found = best
        }
        guard let t = found else { return nil }

        // Parabolic interpolation around the minimum for sub-sample accuracy.
        var refined = Double(t)
        if t > 1, t < maxTau {
            let s0 = d[t - 1], s1 = d[t], s2 = d[t + 1]
            let denom = s0 + s2 - 2 * s1
            if abs(denom) > .ulpOfOne { refined += (s0 - s2) / (2 * denom) }
        }
        let frequency = sampleRate / refined
        guard frequency >= minFrequency * 0.95, frequency <= maxFrequency * 1.05 else { return nil }
        return PitchEstimate(frequency: frequency, clarity: max(0, min(1, 1 - d[t])))
    }
}

/// Steadies tuner readings: median of recent readings (rejects outliers and
/// octave glitches), then a gentle low-pass. Resets on a real note change.
public struct PitchSmoother: Sendable {
    public var windowSize: Int
    public var smoothing: Double
    private var recent: [Double] = []
    private var value: Double?
    private var pendingJumps = 0

    public init(windowSize: Int = 5, smoothing: Double = 0.35) {
        self.windowSize = max(1, windowSize)
        self.smoothing = smoothing
    }

    public mutating func reset() {
        recent.removeAll()
        value = nil
        pendingJumps = 0
    }

    /// Adds a frequency and returns the smoothed frequency.
    public mutating func add(_ frequency: Double) -> Double {
        if let current = value, abs(NoteMath.cents(from: current, to: frequency)) > 60 {
            // Big jump: probably a new note. Accept after it persists.
            pendingJumps += 1
            if pendingJumps < 3 { return current }
            reset()
        } else {
            pendingJumps = 0
        }
        recent.append(frequency)
        if recent.count > windowSize { recent.removeFirst(recent.count - windowSize) }
        let median = recent.sorted()[recent.count / 2]
        let next = value.map { $0 + smoothing * (median - $0) } ?? median
        value = next
        return next
    }
}
