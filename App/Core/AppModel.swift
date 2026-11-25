import CoreData
import Foundation
import Observation
import PracticeKit
import SwiftData
import SwiftUI
import WidgetKit

/// App-wide state and services. Owns the model container, the session
/// controller and everything that reacts to session changes.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let identifiers = AppIdentifiers.current
    let settings: AppSettings
    let sessionController: SessionController
    let audio = AudioTools()
    let recordingFiles: RecordingFiles
    let analysis: RecordingAnalysisService
    /// Records behind every statistic, cached for speed.
    let statsStore: StatsRecordStore
    private(set) var container: ModelContainer
    /// True when the container was built with CloudKit.
    private(set) var isSyncing: Bool

    // Presentation state
    var isShowingActiveSession = false
    var finishDraft: FinishedSession?
    var conflict: SessionConflict?
    var restoredSessionPrompt: ActiveSession?
    var banner: Banner?
    var pendingSyncChange = false
    /// Today/streak/week totals, refreshed after every change.
    private(set) var snapshot: WidgetSnapshot?

    @ObservationIgnored let liveActivity = LiveActivityManager()
    @ObservationIgnored let reminders = ReminderScheduler()
    @ObservationIgnored lazy var watchSync = PhoneWatchSync(model: self)
    @ObservationIgnored private let snapshotStore: WidgetSnapshotStore
    @ObservationIgnored private var remoteChangeObserver: NSObjectProtocol?
    @ObservationIgnored fileprivate var remoteChangeDebounce: Task<Void, Never>?

    private init() {
        let settings = AppSettings(defaults: identifiers.sharedDefaults)
        self.settings = settings
        let store = FileActiveSessionStore(directory: identifiers.sharedDirectory)
        sessionController = SessionController(store: store)
        snapshotStore = WidgetSnapshotStore(directory: identifiers.sharedDirectory)
        recordingFiles = RecordingFiles(identifiers: identifiers)
        analysis = RecordingAnalysisService(files: recordingFiles)
        let isUITesting = LaunchFlags.isUITesting
        statsStore = StatsRecordStore(
            cacheURL: isUITesting ? nil : identifiers.sharedDirectory.appending(path: "stats-records.json"),
            loadInBackground: true)

        let wantsSync = settings.syncEnabled && settings.iCloudSignedIn
        container = Self.buildContainer(sync: wantsSync, identifiers: identifiers)
        isSyncing = wantsSync

        #if DEBUG
        if LaunchFlags.isUITesting { configureForUITests() }
        #endif

        restoredSessionPrompt = DemoScreen.isEnabled ? nil : sessionController.active
        sessionController.addObserver { [weak self] event in self?.handle(event) }
        audio.recorder.onFinish = { [weak self] result in self?.recordingFinished(result) }
        IntentRuntime.performer = self
    }

    private static func buildContainer(sync: Bool, identifiers: AppIdentifiers) -> ModelContainer {
        if let container = try? PracticeStore.makeContainer(identifiers: identifiers, syncEnabled: sync) {
            return container
        }
        // Last resort so the app always opens; data won't persist this launch.
        return try! PracticeStore.makeContainer(identifiers: identifiers, syncEnabled: false, inMemory: true)
    }

    var context: ModelContext { container.mainContext }

    // MARK: Lifecycle

    func didLaunch() {
        if !statsStore.hasCache || LaunchFlags.isUITesting {
            statsStore.rebuild(from: container)
        }
        observeRemoteChanges()
        Task { await refreshICloudStatus() }
        watchSync.activate()
        liveActivity.adopt(sessionController.active)
        // Wait for the stats cache (or rebuild) so widgets never get zeros.
        Task {
            await statsStore.waitForRebuild()
            refreshDerivedState()
        }
        recordingFiles.prune(olderThan: settings.recordingRetentionDays, in: context)
        Task {
            if isSyncing { await recordingFiles.resolveICloud(containerID: identifiers.cloudKitContainer) }
            await recordingFiles.applySync(enabled: isSyncing && settings.syncRecordings, in: context)
        }
    }

    func didBecomeActive() {
        sessionController.reloadFromDisk()
        liveActivity.sync(sessionController.active)
        refreshDerivedState()
    }

    /// Rebuilds the container after the iCloud toggle changes. Deferred while a
    /// session is running so nothing in flight is lost.
    func applySyncSetting() {
        guard !sessionController.isActive else {
            pendingSyncChange = true
            return
        }
        pendingSyncChange = false
        let wantsSync = settings.syncEnabled && settings.iCloudSignedIn
        guard wantsSync != isSyncing else { return }
        try? context.save()
        container = Self.buildContainer(sync: wantsSync, identifiers: identifiers)
        isSyncing = wantsSync
        statsStore.rebuild(from: container)
        refreshDerivedState()
    }

    /// Checks iCloud sign-in off the main thread (it can take seconds) and
    /// switches the store only if the state changed since last launch.
    func refreshICloudStatus() async {
        guard !LaunchFlags.isUITesting else { return }
        let signedIn = await Task.detached(priority: .utility) {
            FileManager.default.ubiquityIdentityToken != nil
        }.value
        guard signedIn != settings.iCloudSignedIn else { return }
        settings.iCloudSignedIn = signedIn
        applySyncSetting()
    }

    /// iCloud imports change the store behind our back: rebuild the stats cache.
    private func observeRemoteChanges() {
        guard remoteChangeObserver == nil else { return }
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.remoteChangeDebounce?.cancel()
                AppModel.shared.remoteChangeDebounce = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    AppModel.shared.statsStore.rebuild(from: AppModel.shared.container)
                    AppModel.shared.refreshDerivedState()
                }
            }
        }
    }

    /// Call after saving, editing or deleting a single session.
    func sessionDidChange(_ session: PracticeSession) {
        statsStore.upsert(session)
        refreshDerivedState()
    }

    func sessionWasDeleted(id: UUID) {
        statsStore.remove(sessionID: id)
        refreshDerivedState()
    }

    /// Call after bulk changes (import, intents, watch deliveries).
    func storeDidChangeInBulk() {
        statsStore.rebuild(from: container)
        Task {
            await statsStore.waitForRebuild()
            refreshDerivedState()
        }
    }

    // MARK: Session actions

    @discardableResult
    func startSession(instrument: Instrument?, item: PracticeItem? = nil, source: SessionSource = .phone) -> ActiveSession {
        let target = item.map { SegmentTarget.item($0.id, title: $0.title) } ?? .general
        let session = sessionController.start(instrument: instrument.map(InstrumentRef.init), target: target, source: source)
        if let instrument { settings.lastInstrumentID = instrument.id }
        isShowingActiveSession = true
        return session
    }

    func switchTo(_ item: PracticeItem?) {
        sessionController.switchTo(item.map { .item($0.id, title: $0.title) } ?? .general)
        if let tempo = item?.lastTempo { audio.metronome.settings.bpm = tempo }
    }

    func beginFinish() {
        audio.stopAll()
        finishDraft = sessionController.finish()
    }

    func save(_ draft: FinishedSession) {
        do {
            let saved = try SessionWriter.insert(draft, into: context)
            statsStore.upsert(saved)
            sessionController.markSaved(draft)
            finishDraft = nil
            isShowingActiveSession = false
            applyPendingSyncChange()
        } catch {
            banner = Banner(message: String(localized: "Couldn't save the session. Try again."), isError: true)
        }
    }

    func discardActiveSession() {
        audio.stopAll()
        sessionController.discard()
        finishDraft = nil
        isShowingActiveSession = false
        applyPendingSyncChange()
    }

    func resolveConflict(merge: Bool) {
        guard let conflict else { return }
        sessionController.resolveConflict(winner: conflict.winner, loser: conflict.loser, merge: merge)
        self.conflict = nil
    }

    private func applyPendingSyncChange() {
        if pendingSyncChange { applySyncSetting() }
    }

    // MARK: Events

    private func handle(_ event: SessionEvent) {
        liveActivity.handle(event)
        watchSync.send(event)
        if case .finished = event { refreshDerivedState() }
        if case .discarded = event { refreshDerivedState() }
        Task { await reminders.updateLongSessionNudge(for: sessionController.active) }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
    }

    /// Recomputes the widget snapshot, watch context and reminders.
    func refreshDerivedState() {
        let records = statsStore.records
        let lastInstrument = settings.lastInstrumentID.flatMap { try? SessionWriter.fetchInstrument(id: $0, in: context) }
        let snapshot = WidgetSnapshot.make(records: records, goal: settings.goal,
                                           lastInstrument: lastInstrument.map(InstrumentRef.init))
        self.snapshot = snapshot
        try? snapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        watchSync.pushContext(snapshot: snapshot)
        let minutes = DurationText.minutes(snapshot.todaySeconds)
        Task { await reminders.reschedule(settings: settings, todayMinutes: minutes) }
    }

    func todayMinutes() -> Int {
        let interval = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval()
        let start = interval.start, end = interval.end
        let sessions = (try? context.fetch(FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end }))) ?? []
        return DurationText.minutes(sessions.reduce(0) { $0 + $1.activeDuration })
    }

    // MARK: Recording

    func startRecording() {
        Task { await audio.recorder.start(storage: recordingFiles.storage) }
    }

    private func recordingFinished(_ result: RecordingResult) {
        let active = sessionController.active
        let recording = Recording(
            createdAt: result.startedAt, duration: result.duration, audioFileName: result.fileName,
            offsetInSession: active.map { result.startedAt.timeIntervalSince($0.startDate) },
            title: active?.currentTarget.title ?? "")
        recording.sessionRefID = active?.id
        recording.segmentRefID = active?.currentSegment?.id
        if let itemID = active?.currentTarget.itemID {
            recording.item = try? SessionWriter.fetchItem(id: itemID, in: context)
        }
        context.insert(recording)
        try? context.save()
        analysis.analyze(recording, in: context)
        if isSyncing, settings.syncRecordings {
            Task { await recordingFiles.applySync(enabled: true, in: context) }
        }
        if result.interrupted {
            banner = Banner(message: String(localized: "Recording stopped due to an interruption. It was saved."), isError: false)
        }
    }

    // MARK: UI testing

    #if DEBUG
    private func configureForUITests() {
        container = try! PracticeStore.makeContainer(identifiers: identifiers, syncEnabled: false, inMemory: true)
        isSyncing = false
        if sessionController.active != nil { sessionController.discard() }
        if ProcessInfo.processInfo.arguments.contains("-demoData") {
            settings.hasOnboarded = true
            DemoData.seed(into: context)
            settings.lastInstrumentID = (try? context.fetch(FetchDescriptor<Instrument>(sortBy: [SortDescriptor(\.sortIndex)])))?.first?.id
            if DemoScreen.has("-demoSession") { DemoScreen.startSession(in: self) }
            if DemoScreen.has("-demoReport") {
                let url = URL.documentsDirectory.appending(path: "demo-report.pdf")
                _ = PracticeReportRenderer.renderPDF(context: context, goal: settings.goal, period: .last30Days, to: url)
            }
        } else if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") {
            settings.hasOnboarded = true
            let violin = Instrument(preset: InstrumentPreset.preset(forKey: "violin")!)
            context.insert(violin)
            context.insert(PracticeItem(title: "Scales", category: .scale, instrument: violin))
            context.insert(PracticeItem(title: "Bach Chaconne", composer: "J. S. Bach", instrument: violin))
            try? context.save()
        } else {
            settings.hasOnboarded = false
        }
    }
    #endif
}

struct SessionConflict: Identifiable, Equatable {
    var winner: ActiveSession
    var loser: ActiveSession
    var id: UUID { loser.id }
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var isError: Bool
}

// MARK: - Intents bridge

extension AppModel: PracticeIntentPerforming {
    var modelContainer: ModelContainer { container }

    func startSession(instrumentID: UUID?, itemID: UUID?, source: SessionSource) -> ActiveSession {
        let instrumentID = instrumentID ?? settings.lastInstrumentID
        let instrument = instrumentID.flatMap { try? SessionWriter.fetchInstrument(id: $0, in: context) }
        let item = itemID.flatMap { try? SessionWriter.fetchItem(id: $0, in: context) }
        return startSession(instrument: instrument ?? item?.instrument, item: item, source: source)
    }

    func nextItemTarget(after current: SegmentTarget) -> SegmentTarget? {
        let items = RecentItems.fetch(in: context, instrumentID: sessionController.active?.instrument?.id, limit: 5)
        guard !items.isEmpty else { return nil }
        let index = items.firstIndex { $0.id == current.itemID }.map { ($0 + 1) % items.count } ?? 0
        return .item(items[index].id, title: items[index].title)
    }

    func requestFinishSheet() {
        isShowingActiveSession = true
        beginFinish()
    }

    func saveWithoutReview() {
        guard let finished = sessionController.finish() else { return }
        save(finished)
    }

    func dataDidChange() {
        storeDidChangeInBulk()
    }
}
