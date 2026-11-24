import Foundation
import SwiftData
@testable import PracticeKit

/// A controllable clock for engine tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
    func set(_ date: Date) { lock.withLock { current = date } }

    var engine: SessionEngine { SessionEngine(now: { [self] in now }) }
}

func calendar(_ tz: String) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tz)!
    cal.firstWeekday = 2 // Monday
    return cal
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, tz: String = "America/New_York") -> Date {
    calendar(tz).date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@MainActor
func makeTestContainer() throws -> ModelContainer {
    try PracticeStore.makeContainer(
        identifiers: AppIdentifiers(appGroup: nil, cloudKitContainer: nil),
        syncEnabled: false,
        inMemory: true
    )
}

func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "PracticeKitTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let pieceA = SegmentTarget.item(UUID(), title: "Piece A")
let pieceB = SegmentTarget.item(UUID(), title: "Piece B")
let scales = SegmentTarget.item(UUID(), title: "Scales")
