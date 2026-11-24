import AppIntents
import Foundation
import PracticeKit
import SwiftData

/// "Log 20 minutes of scales in Ostinato".
struct LogPracticeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Practice"
    static let description = IntentDescription("Adds a practice session you already did.")

    @Parameter(title: "Minutes", inclusiveRange: (1, 1_440)) var minutes: Int
    @Parameter(title: "Item") var item: PracticeItemEntity?
    @Parameter(title: "Instrument") var instrument: InstrumentEntity?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$minutes) minutes of \(\.$item)") {
            \.$instrument
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (1...ManualSessionBuilder.maxMinutes).contains(minutes) else { throw IntentError.invalidMinutes }
        let end = date ?? Date()
        let start = end.addingTimeInterval(-TimeInterval(minutes * 60))
        let target = item.map { SegmentTarget.item($0.id, title: $0.title) } ?? .general
        guard let finished = ManualSessionBuilder.make(
            start: start, segments: [ManualSegment(target: target, minutes: minutes)],
            instrumentID: instrument?.id, source: .siri)
        else { throw IntentError.invalidMinutes }
        try SessionWriter.insert(finished, into: IntentRuntime.container().mainContext)
        IntentRuntime.didChange()
        let spoken = DurationText.spoken(finished.activeDuration)
        if let item { return .result(dialog: "Logged \(spoken) of \(item.title).") }
        return .result(dialog: "Logged \(spoken) of practice.")
    }
}

/// "How much did I practice this week?"
struct GetPracticeSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Practice Summary"
    static let description = IntentDescription("Tells you how much you practiced.")

    @Parameter(title: "Range", default: .week) var range: SummaryRange

    static var parameterSummary: some ParameterSummary { Summary("Practice summary for \(\.$range)") }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let calendar = Calendar.current
        let now = Date()
        let component: Calendar.Component = switch range {
        case .today: .day
        case .week: .weekOfYear
        case .month: .month
        }
        let interval = calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
        let start = interval.start, end = interval.end
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate < end })
        let sessions = try IntentRuntime.container().mainContext.fetch(descriptor)
        var total = sessions.reduce(0) { $0 + $1.activeDuration }
        if let active = IntentRuntime.controller.active, interval.contains(active.startDate) {
            total += active.elapsed(at: now)
        }
        let spoken = DurationText.spoken(total)
        let text: String = switch range {
        case .today: total > 0 ? String(localized: "You practiced \(spoken) today.") : String(localized: "No practice logged today yet.")
        case .week: total > 0 ? String(localized: "You practiced \(spoken) this week.") : String(localized: "No practice logged this week yet.")
        case .month: total > 0 ? String(localized: "You practiced \(spoken) this month.") : String(localized: "No practice logged this month yet.")
        }
        return .result(value: text, dialog: "\(text)")
    }
}
