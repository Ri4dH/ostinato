import Foundation
import Observation
import PracticeKit

/// The app's audio engines, created lazily on first use.
@MainActor
@Observable
final class AudioTools {
    @ObservationIgnored private var _metronome: MetronomeEngine?
    @ObservationIgnored private var _drone: DroneEngine?
    @ObservationIgnored private var _tuner: TunerEngine?
    let recorder = PracticeRecorder()
    @ObservationIgnored private var _player: RecordingPlayer?

    var metronome: MetronomeEngine {
        if let _metronome { return _metronome }
        let engine = MetronomeEngine(settings: AppModel.shared.settings.metronome)
        _metronome = engine
        return engine
    }

    var drone: DroneEngine {
        if let _drone { return _drone }
        let engine = DroneEngine(settings: AppModel.shared.settings.drone)
        _drone = engine
        return engine
    }

    var tuner: TunerEngine {
        if let _tuner { return _tuner }
        let engine = TunerEngine()
        _tuner = engine
        return engine
    }

    var player: RecordingPlayer {
        if let _player { return _player }
        let player = RecordingPlayer()
        _player = player
        return player
    }

    func stopAll() {
        _metronome?.stop()
        _drone?.stop()
        _tuner?.stop()
        recorder.stop()
        _player?.stop()
    }
}

/// Items practiced most recently, for "Continue with…" chips and the
/// Live Activity's Next button.
@MainActor
enum RecentItems {
    static func fetch(in context: ModelContext, instrumentID: UUID?, limit: Int) -> [PracticeItem] {
        var descriptor = FetchDescriptor<SessionSegment>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 200
        let segments = (try? context.fetch(descriptor)) ?? []
        var seen = Set<UUID>()
        var result: [PracticeItem] = []
        for segment in segments {
            guard let item = segment.item, !item.isArchived, seen.insert(item.id).inserted else { continue }
            if let instrumentID, item.instrument?.id != instrumentID { continue }
            result.append(item)
            if result.count == limit { break }
        }
        if result.count < limit {
            // Fill with recently edited items so new users see their repertoire.
            let archived = ItemStatus.archived.rawValue
            var items = FetchDescriptor<PracticeItem>(
                predicate: #Predicate { $0.statusRaw != archived },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            items.fetchLimit = 20
            for item in (try? context.fetch(items)) ?? [] where seen.insert(item.id).inserted {
                if let instrumentID, item.instrument?.id != instrumentID { continue }
                result.append(item)
                if result.count == limit { break }
            }
        }
        return result
    }
}

import SwiftData
