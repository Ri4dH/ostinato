import Foundation
import Observation
import PracticeKit
import SwiftData

/// Finds, moves and deletes recording audio files. Metadata stays in SwiftData.
@MainActor
@Observable
final class RecordingFiles {
    enum Availability: Equatable {
        case ready(URL)
        case downloading
        /// Metadata synced but the audio only exists on another device.
        case onAnotherDevice
    }

    private(set) var storage: RecordingStorage
    private(set) var isMoving = false
    private let identifiers: AppIdentifiers

    init(identifiers: AppIdentifiers) {
        self.identifiers = identifiers
        storage = RecordingStorage.standard(identifiers: identifiers)
    }

    var iCloudAvailable: Bool { storage.iCloudBase != nil }

    /// Resolves the iCloud Drive container off the main thread (it can block).
    func resolveICloud(containerID: String?) async {
        guard let containerID else { return }
        let url = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: containerID)
        }.value
        storage = RecordingStorage.standard(identifiers: identifiers, ubiquityBase: url)
        try? storage.ensureDirectories()
    }

    func availability(of recording: Recording) -> Availability {
        guard let url = storage.url(for: recording.audioFileName, at: recording.fileLocation) else {
            return .onAnotherDevice
        }
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            if recording.fileLocation == .iCloud,
               let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                return .downloading
            }
            return .ready(url)
        }
        if recording.fileLocation == .iCloud {
            // Placeholder may exist under a hidden ".name.icloud" file.
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .downloading
        }
        return .onAnotherDevice
    }

    func delete(_ recording: Recording, in context: ModelContext) {
        if let url = storage.url(for: recording.audioFileName, at: recording.fileLocation) {
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: nil) { try? FileManager.default.removeItem(at: $0) }
        }
        context.delete(recording)
        try? context.save()
    }

    /// Moves every file to iCloud Drive (or back to local) to match the
    /// setting. Resumable: each file is moved and recorded individually.
    func applySync(enabled: Bool, in context: ModelContext) async {
        guard !isMoving else { return }
        let target: FileLocation = enabled && iCloudAvailable ? .iCloud : .local
        let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        isMoving = true
        defer { isMoving = false }
        for recording in recordings where recording.fileLocation != target {
            guard let from = storage.url(for: recording.audioFileName, at: recording.fileLocation),
                  let to = storage.url(for: recording.audioFileName, at: target),
                  FileManager.default.fileExists(atPath: from.path(percentEncoded: false)) else { continue }
            let toICloud = target == .iCloud
            let moved = await Task.detached(priority: .utility) { () -> Bool in
                do {
                    try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if toICloud {
                        try FileManager.default.setUbiquitous(true, itemAt: from, destinationURL: to)
                    } else {
                        try FileManager.default.setUbiquitous(false, itemAt: from, destinationURL: to)
                    }
                    return true
                } catch {
                    return false
                }
            }.value
            if moved {
                recording.fileLocation = target
                try? context.save()
            }
        }
    }

    /// Deletes recordings older than `days` (0 = keep forever).
    func prune(olderThan days: Int, in context: ModelContext, now: Date = Date()) {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        let old = (try? context.fetch(FetchDescriptor<Recording>(predicate: #Predicate { $0.createdAt < cutoff }))) ?? []
        for recording in old { delete(recording, in: context) }
    }

    func bytesUsed() -> (local: Int64, iCloud: Int64) {
        (storage.bytesUsed(at: .local), storage.bytesUsed(at: .iCloud))
    }

    func deleteAllFiles() {
        for location in FileLocation.allCases {
            guard let base = storage.baseDirectory(for: location) else { continue }
            try? FileManager.default.removeItem(at: base)
        }
        try? storage.ensureDirectories()
    }
}
