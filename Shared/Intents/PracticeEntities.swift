import AppIntents
import Foundation
import PracticeKit
import SwiftData

struct InstrumentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Instrument"
    static let defaultQuery = InstrumentQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ instrument: Instrument) { self.init(id: instrument.id, name: instrument.name) }
}

struct InstrumentQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [InstrumentEntity] {
        try fetch().filter { identifiers.contains($0.id) }.map(InstrumentEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [InstrumentEntity] {
        try fetch().filter { $0.name.localizedStandardContains(string) }.map(InstrumentEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [InstrumentEntity] {
        try fetch().map(InstrumentEntity.init)
    }

    @MainActor
    private func fetch() throws -> [Instrument] {
        let descriptor = FetchDescriptor<Instrument>(
            predicate: #Predicate { !$0.isArchived }, sortBy: [SortDescriptor(\.sortIndex)])
        return try IntentRuntime.container().mainContext.fetch(descriptor)
    }
}

struct PracticeItemEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Practice Item"
    static let defaultQuery = PracticeItemQuery()

    var id: UUID
    var title: String
    var subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        if let subtitle { return DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)") }
        return DisplayRepresentation(title: "\(title)")
    }

    init(id: UUID, title: String, subtitle: String?) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    init(_ item: PracticeItem) {
        self.init(id: item.id, title: item.title, subtitle: item.composer ?? item.instrument?.name)
    }
}

struct PracticeItemQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PracticeItemEntity] {
        try fetch().filter { identifiers.contains($0.id) }.map(PracticeItemEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [PracticeItemEntity] {
        try fetch().filter {
            $0.title.localizedStandardContains(string) || ($0.composer?.localizedStandardContains(string) ?? false)
        }.map(PracticeItemEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [PracticeItemEntity] {
        try fetch().prefix(30).map(PracticeItemEntity.init)
    }

    @MainActor
    private func fetch() throws -> [PracticeItem] {
        let archived = ItemStatus.archived.rawValue
        let descriptor = FetchDescriptor<PracticeItem>(
            predicate: #Predicate { $0.statusRaw != archived },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try IntentRuntime.container().mainContext.fetch(descriptor)
    }
}

enum SummaryRange: String, AppEnum {
    case today, week, month

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Range"
    static let caseDisplayRepresentations: [SummaryRange: DisplayRepresentation] = [
        .today: "Today",
        .week: "This Week",
        .month: "This Month"
    ]
}
