import Foundation
import Observation
import SwiftData

/// Background loader so a full rebuild never blocks the main thread.
@ModelActor
public actor SessionRecordRebuilder {
    public func loadAll() throws -> [SessionRecord] {
        try SessionRecordLoader.load(from: modelContext)
    }
}

/// The records every statistic is computed from, kept in a small cache file.
///
/// Reading thousands of sessions through SwiftData is slow, so the app reads
/// this cache instantly, updates single records when a session is saved,
/// edited or deleted, and only rebuilds everything in the background (after
/// an import or an iCloud change).
@MainActor
@Observable
public final class StatsRecordStore {
    public private(set) var records: [SessionRecord] = []
    public private(set) var isRebuilding = false
    /// Bumped on every change so views can refresh.
    public private(set) var revision = 0

    @ObservationIgnored private let cacheURL: URL?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

    /// Reads the cache synchronously (tests, small caches).
    public init(cacheURL: URL?) {
        self.cacheURL = cacheURL
        records = cacheURL.flatMap(Self.readCache) ?? []
    }

    /// Reads the cache off the main thread; `records` fills in when ready.
    public init(cacheURL: URL?, loadInBackground: Bool) {
        self.cacheURL = cacheURL
        guard loadInBackground else {
            records = cacheURL.flatMap(Self.readCache) ?? []
            return
        }
        isRebuilding = true
        rebuildTask = Task { [cacheURL] in
            let cached = await Task.detached(priority: .userInitiated) { cacheURL.flatMap(Self.readCache) }.value
            if let cached, self.records.isEmpty { self.records = cached; self.revision += 1 }
            self.isRebuilding = false
        }
    }

    nonisolated private static func readCache(_ url: URL) -> [SessionRecord]? {
        guard let data = try? Data(contentsOf: url),
              let cached = try? decoder.decode(Cache.self, from: data), cached.version == Cache.currentVersion
        else { return nil }
        return cached.records
    }

    public var hasCache: Bool { cacheURL.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false }

    /// Adds or replaces the record for one session.
    public func upsert(_ session: PracticeSession) {
        let record = SessionRecord(session)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            let index = records.firstIndex { $0.startDate > record.startDate } ?? records.endIndex
            records.insert(record, at: index)
        }
        changed()
    }

    public func remove(sessionID: UUID) {
        records.removeAll { $0.id == sessionID }
        changed()
    }

    public func replaceAll(_ newRecords: [SessionRecord]) {
        records = newRecords.sorted { $0.startDate < $1.startDate }
        changed()
    }

    /// Rebuilds from the store on a background actor. Cancels any rebuild in flight.
    public func rebuild(from container: ModelContainer) {
        let previous = rebuildTask
        isRebuilding = true
        rebuildTask = Task {
            await previous?.value
            let rebuilder = SessionRecordRebuilder(modelContainer: container)
            let loaded = try? await rebuilder.loadAll()
            guard !Task.isCancelled else { return }
            if let loaded { replaceAll(loaded) }
            isRebuilding = false
        }
    }

    public func waitForRebuild() async { await rebuildTask?.value }

    private func changed() {
        revision += 1
        guard let cacheURL else { return }
        let snapshot = Cache(version: Cache.currentVersion, records: records)
        Task.detached(priority: .utility) {
            guard let data = try? Self.encoder.encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    struct Cache: Codable, Sendable {
        static let currentVersion = 1
        var version: Int
        var records: [SessionRecord]
    }

    nonisolated static let encoder: PropertyListEncoder = {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return e
    }()

    nonisolated static let decoder = PropertyListDecoder()
}
