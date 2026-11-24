import AVFoundation
import Foundation

/// Reads an audio file into mono Float samples for analysis.
public enum AudioFileDecoder {
    public enum DecodeError: Error { case unreadable }

    /// Decodes up to `maxSeconds` (default 10 minutes) and mixes to mono.
    public static func monoSamples(url: URL, maxSeconds: Double = 600) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(min(Double(file.length), maxSeconds * format.sampleRate))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw DecodeError.unreadable
        }
        try file.read(into: buffer, frameCount: frames)
        guard let channels = buffer.floatChannelData else { throw DecodeError.unreadable }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = Array(UnsafeBufferPointer(start: channels[0], count: count))
        if channelCount > 1 {
            for c in 1..<channelCount {
                let other = UnsafeBufferPointer(start: channels[c], count: count)
                for i in 0..<count { mono[i] += other[i] }
            }
            let scale = 1 / Float(channelCount)
            for i in 0..<count { mono[i] *= scale }
        }
        return (mono, format.sampleRate)
    }

    /// Decodes and analyzes off the calling actor.
    @concurrent
    public static func analyze(url: URL) async throws -> RecordingAnalysis {
        let (samples, rate) = try monoSamples(url: url)
        try Task.checkCancellation()
        return RecordingAnalyzer().analyze(samples, sampleRate: rate)
    }
}
