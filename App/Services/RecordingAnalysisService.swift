import Foundation
import Observation
import PracticeKit
import SwiftData

/// Runs on-device analysis for recordings and caches the result in
/// `Recording.analysisJSON`. One task per recording; cancellable.
@MainActor
@Observable
final class RecordingAnalysisService {
    private(set) var inProgress: Set<UUID> = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private unowned let files: RecordingFiles

    init(files: RecordingFiles) {
        self.files = files
    }

    func analysis(for recording: Recording) -> RecordingAnalysis? {
        RecordingAnalysis.decode(recording.analysisJSON)
    }

    func isAnalyzing(_ recording: Recording) -> Bool { inProgress.contains(recording.id) }

    func analyze(_ recording: Recording, in context: ModelContext) {
        guard !inProgress.contains(recording.id), case .ready(let url) = files.availability(of: recording) else { return }
        let id = recording.id
        inProgress.insert(id)
        tasks[id] = Task { [weak self] in
            let result = try? await AudioFileDecoder.analyze(url: url)
            guard let self else { return }
            self.inProgress.remove(id)
            self.tasks[id] = nil
            guard !Task.isCancelled, let result else { return }
            recording.analysisJSON = result.encoded()
            try? context.save()
        }
    }

    func cancel(_ recording: Recording) {
        tasks[recording.id]?.cancel()
        tasks[recording.id] = nil
        inProgress.remove(recording.id)
    }

    /// Saves the analyzed tempo to the recording's item.
    @discardableResult
    func saveTempo(of recording: Recording, in context: ModelContext) -> Int? {
        guard let item = recording.item, let bpm = analysis(for: recording)?.roundedBPM else { return nil }
        context.insert(item.logTempo(bpm, source: .analysis, date: recording.createdAt))
        try? context.save()
        return bpm
    }
}
