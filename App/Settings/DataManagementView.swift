import PracticeKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Export (CSV, JSON, recordings, weekly report), import, and delete all.
struct DataManagementView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var csvURL: URL?
    @State private var backupURL: URL?
    @State private var recordingsZipURL: URL?
    @State private var reportURL: URL?
    @State private var importing = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false

    var body: some View {
        Form {
            Section {
                exportRow("Practice log (CSV)", detail: "One row per item practiced. Opens in any spreadsheet.",
                          url: csvURL, prepare: makeCSV)
                exportRow("Weekly report (PDF)", detail: "Minutes per day and per item, with notes. Good for your teacher.",
                          url: reportURL, prepare: makeReport)
            } header: {
                Text("Share")
            }

            Section {
                exportRow("Full backup (JSON)", detail: "Everything except audio files.", url: backupURL, prepare: makeBackup)
                exportRow("Recordings (ZIP)", detail: "All audio files on this device.", url: recordingsZipURL, prepare: makeRecordingsZip)
                Button("Import Backup", systemImage: "square.and.arrow.down") { importing = true }
            } header: {
                Text("Backup")
            } footer: {
                Text("Importing adds what's missing and never creates duplicates.")
            }

            Section {
                Button("Delete All Data", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Removes every session, item, instrument and recording from this device and your iCloud.")
            }
        }
        .navigationTitle("Your Data")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { importBackup(url) }
        }
        .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { confirmDeleteAgain = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Export a backup first if you might want it later.")
        }
        .alert("Are you sure?", isPresented: $confirmDeleteAgain) {
            Button("Delete Everything", role: .destructive, action: deleteAll)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All practice history and recordings will be permanently deleted.")
        }
    }

    private func exportRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, url: URL?, prepare: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url {
                ShareLink(item: url) { Label(title, systemImage: "square.and.arrow.up") }
            } else {
                Button { prepare() } label: { Label(title, systemImage: "doc.badge.plus") }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func exportDirectory() -> URL {
        let dir = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var stamp: String { Date().formatted(.iso8601.year().month().day()) }

    private func makeCSV() {
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>())) ?? []
        let url = exportDirectory().appending(path: "Ostinato-\(stamp).csv")
        do {
            try CSVExporter.csv(CSVExporter.rows(from: sessions)).write(to: url, atomically: true, encoding: .utf8)
            csvURL = url
        } catch { message = String(localized: "Couldn't create the file. Try again.") }
    }

    private func makeBackup() {
        let url = exportDirectory().appending(path: "Ostinato-backup-\(stamp).json")
        do {
            let data = try BackupService.encode(BackupService.makeBackup(from: context, goal: settings.goal))
            try data.write(to: url, options: .atomic)
            backupURL = url
        } catch { message = String(localized: "Couldn't create the backup. Try again.") }
    }

    private func makeRecordingsZip() {
        let source = model.recordingFiles.storage.localBase
        let destination = exportDirectory().appending(path: "Ostinato-recordings-\(stamp).zip")
        var coordinationError: NSError?
        // The system zips a directory when it's read "for uploading".
        NSFileCoordinator().coordinate(readingItemAt: source, options: .forUploading, error: &coordinationError) { zipped in
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.copyItem(at: zipped, to: destination)
        }
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            recordingsZipURL = destination
        } else {
            message = String(localized: "No recordings on this device yet.")
        }
    }

    private func makeReport() {
        let url = exportDirectory().appending(path: "Ostinato-week-\(stamp).pdf")
        if WeeklyReportRenderer.renderPDF(context: context, goal: settings.goal, to: url) {
            reportURL = url
        } else {
            message = String(localized: "Couldn't create the report. Try again.")
        }
    }

    private func importBackup(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size < 200_000_000 else { throw BackupError.unreadable }
            let document = try BackupService.decode(Data(contentsOf: url))
            let summary = try BackupService.merge(document, into: context)
            model.storeDidChangeInBulk()
            message = String(localized: "Added \(summary.inserted) records, updated \(summary.updated). \(summary.skipped) were already here.")
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? String(localized: "This file couldn't be imported.")
        }
    }

    private func deleteAll() {
        model.discardActiveSession()
        try? context.delete(model: Recording.self)
        try? context.delete(model: TempoEntry.self)
        try? context.delete(model: PauseInterval.self)
        try? context.delete(model: SessionSegment.self)
        try? context.delete(model: PracticeSession.self)
        try? context.delete(model: PracticeItem.self)
        try? context.delete(model: Instrument.self)
        try? context.save()
        model.recordingFiles.deleteAllFiles()
        settings.resetAll()
        settings.hasOnboarded = false
        model.statsStore.replaceAll([])
        model.refreshDerivedState()
    }
}
