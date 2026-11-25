import Foundation
import SwiftData
import Testing
@testable import PracticeKit

@Suite("Export and import")
@MainActor
struct ExportTests {
    func seed(_ context: ModelContext) throws -> (Instrument, PracticeItem) {
        let violin = Instrument(name: "Violin", presetKey: "violin")
        let chaconne = PracticeItem(title: "Chaconne, BWV 1004", composer: "Bach", category: .piece, instrument: violin)
        context.insert(violin)
        context.insert(chaconne)
        context.insert(chaconne.logTempo(60, source: .metronome))
        let clock = TestClock(date(2026, 3, 2, 18))
        let engine = clock.engine
        var s = engine.start(instrument: InstrumentRef(violin), target: .label("Warm-up"), source: .phone)
        clock.advance(600)
        engine.switchTo(.item(chaconne.id, title: chaconne.title), in: &s)
        clock.advance(1_800)
        var finished = engine.finish(s)
        finished.rating = 4
        finished.focus = 3
        finished.tags = ["lesson"]
        finished.notes = "Bars 1-8, \"slow\""
        let session = try SessionWriter.insert(finished, into: context)
        let rec = Recording(audioFileName: "\(UUID().uuidString).m4a", title: "Take 1")
        context.insert(rec)
        rec.session = session
        rec.item = chaconne
        try context.save()
        return (violin, chaconne)
    }

    @Test func csvHasOneRowPerSegmentAndEscapes() throws {
        let container = try makeTestContainer()
        _ = try seed(container.mainContext)
        let sessions = try container.mainContext.fetch(FetchDescriptor<PracticeSession>())
        let csv = CSVExporter.csv(CSVExporter.rows(from: sessions), timeZone: TimeZone(identifier: "America/New_York")!)
        let lines = csv.split(separator: "\r\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "date,start,end,minutes,instrument,item,category,session_rating,focus,tags,notes")
        #expect(lines[1] == "2026-03-02,18:00,18:10,10.0,Violin,Warm-up,,4,3,lesson,\"Bars 1-8, \"\"slow\"\"\"")
        #expect(lines[2].hasPrefix("2026-03-02,18:10,18:40,30.0,Violin,\"Chaconne, BWV 1004\",piece,4,3"))
    }

    @Test func csvBlocksFormulaInjection() {
        #expect(CSVExporter.escape("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSVExporter.escape("-12") == "-12")
        #expect(CSVExporter.escape("@SUM") == "'@SUM")
    }

    @Test func jsonRoundTripMergesWithoutDuplicates() throws {
        let source = try makeTestContainer()
        _ = try seed(source.mainContext)
        let goal = GoalSettings(dailyMinutes: 45, daysPerWeek: 4)
        let data = try BackupService.encode(BackupService.makeBackup(from: source.mainContext, goal: goal))

        let target = try makeTestContainer()
        let doc = try BackupService.decode(data)
        #expect(doc.goal == goal)
        let first = try BackupService.merge(doc, into: target.mainContext)
        #expect(first.inserted == 5) // instrument, item, session, tempo, recording
        let second = try BackupService.merge(doc, into: target.mainContext)
        #expect(second.inserted == 0)

        let ctx = target.mainContext
        #expect(try ctx.fetchCount(FetchDescriptor<Instrument>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<PracticeItem>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<SessionSegment>()) == 2)
        #expect(try ctx.fetchCount(FetchDescriptor<TempoEntry>()) == 1)
        #expect(try ctx.fetchCount(FetchDescriptor<Recording>()) == 1)

        let session = try #require(try ctx.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(session.instrument?.name == "Violin")
        #expect(session.sortedSegments.last?.item?.title == "Chaconne, BWV 1004")
        #expect(session.recordings?.first?.item?.composer == "Bach")
        #expect(session.activeDuration == 2_400)
    }

    @Test func importUpdatesOnlyNewerItems() throws {
        let container = try makeTestContainer()
        let (_, item) = try seed(container.mainContext)
        var doc = try BackupService.makeBackup(from: container.mainContext, goal: nil)
        doc.items[0].title = "Older title"
        doc.items[0].updatedAt = item.updatedAt.addingTimeInterval(-60)
        _ = try BackupService.merge(doc, into: container.mainContext)
        #expect(item.title == "Chaconne, BWV 1004")

        doc.items[0].title = "Newer title"
        doc.items[0].updatedAt = item.updatedAt.addingTimeInterval(60)
        let summary = try BackupService.merge(doc, into: container.mainContext)
        #expect(summary.updated == 1)
        #expect(item.title == "Newer title")
    }

    @Test func importRejectsUnsafeRecordingPathsAndNewerVersions() throws {
        let container = try makeTestContainer()
        var doc = try BackupService.makeBackup(from: container.mainContext, goal: nil)
        doc.recordings = [.init(id: UUID(), createdAt: Date(), duration: 1, audioFileName: "../../etc/passwd",
                                fileLocation: "local", offsetInSession: nil, title: "",
                                sessionID: nil, segmentID: nil, itemID: nil)]
        let summary = try BackupService.merge(doc, into: container.mainContext)
        #expect(summary.inserted == 0)
        #expect(summary.skipped == 1)

        doc.version = 99
        let data = try BackupService.encode(doc)
        #expect(throws: BackupError.unsupportedVersion(99)) { try BackupService.decode(data) }
        #expect(throws: BackupError.unreadable) { try BackupService.decode(Data("nope".utf8)) }
    }

    @Test func recordingFileNameValidation() {
        let storage = RecordingStorage(localBase: URL(filePath: "/tmp/rec"), iCloudBase: nil)
        #expect(RecordingStorage.isValidFileName("A1B2-c3.m4a"))
        for bad in ["", "../x.m4a", "a/b.m4a", ".hidden", "a\\b", "x..m4a", String(repeating: "a", count: 200)] {
            #expect(!RecordingStorage.isValidFileName(bad))
        }
        #expect(storage.url(for: "take.m4a", at: .local)?.path == "/tmp/rec/take.m4a")
        #expect(storage.url(for: "take.m4a", at: .iCloud) == nil)
    }
}

@Suite("Report periods")
struct ReportPeriodTests {
    let ny = calendar("America/New_York")   // weeks start Monday in this helper
    let now = date(2026, 3, 4, 15)          // Wednesday

    @Test func weeks() {
        let thisWeek = ReportPeriod.thisWeek.interval(now: now, calendar: ny)
        #expect(thisWeek.start == ny.startOfDay(for: date(2026, 3, 2)))
        #expect(thisWeek.end == ny.startOfDay(for: date(2026, 3, 9)))
        let lastWeek = ReportPeriod.lastWeek.interval(now: now, calendar: ny)
        #expect(lastWeek.start == ny.startOfDay(for: date(2026, 2, 23)))
        #expect(lastWeek.end == thisWeek.start)
    }

    @Test func months() {
        let lastMonth = ReportPeriod.lastMonth.interval(now: now, calendar: ny)
        #expect(lastMonth.start == ny.startOfDay(for: date(2026, 2, 1)))
        #expect(lastMonth.end == ny.startOfDay(for: date(2026, 3, 1)))
        #expect(ReportPeriod.thisMonth.interval(now: now, calendar: ny).end == ny.startOfDay(for: date(2026, 4, 1)))
    }

    @Test func lastThirtyDaysIncludesToday() {
        let interval = ReportPeriod.last30Days.interval(now: now, calendar: ny)
        #expect(interval.contains(now))
        #expect(ny.dateComponents([.day], from: interval.start, to: interval.end).day == 30)
        #expect(ReportPeriod.last30Days.fileStem(now: now, calendar: ny) == "2026-02-03_to_2026-03-04")
    }
}
