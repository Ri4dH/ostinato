import PracticeKit
import SwiftData
import SwiftUI

/// "Log past session": date, start, instrument, segments, rating, notes, tags.
struct ManualLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]
    @Query(filter: #Predicate<PracticeItem> { $0.statusRaw != "archived" }, sort: \PracticeItem.title)
    private var items: [PracticeItem]

    @State private var start = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
    @State private var instrumentID: UUID?
    @State private var segments: [ManualSegment] = [ManualSegment(target: .general, minutes: 30)]
    @State private var rating: Int?
    @State private var focus: Int?
    @State private var notes = ""
    @State private var tags: [String] = []

    private var totalMinutes: Int { segments.reduce(0) { $0 + max(0, $1.minutes) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Started", selection: $start, in: ...Date())
                    if !instruments.isEmpty {
                        Picker("Instrument", selection: $instrumentID) {
                            Text("None").tag(UUID?.none)
                            ForEach(instruments) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }

                Section {
                    ForEach($segments) { $segment in
                        ManualSegmentRow(segment: $segment, items: items)
                    }
                    .onDelete { segments.remove(atOffsets: $0) }
                    Button("Add Item", systemImage: "plus") {
                        segments.append(ManualSegment(target: .general, minutes: 10))
                    }
                } header: {
                    Text("What you worked on")
                } footer: {
                    Text("Total \(totalMinutes) min")
                }

                Section("How did it go?") {
                    RatingPicker(title: "Session", symbol: "star", value: $rating)
                    RatingPicker(title: "Focus", symbol: "circle", value: $focus)
                }
                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...6)
                }
                Section("Tags") { TagEditor(tags: $tags) }
            }
            .navigationTitle("Log Past Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(totalMinutes == 0)
                }
            }
            .onAppear { instrumentID = instrumentID ?? settings.lastInstrumentID ?? instruments.first?.id }
        }
    }

    private func save() {
        guard let finished = ManualSessionBuilder.make(
            start: start, segments: segments, instrumentID: instrumentID, rating: rating, focus: focus,
            notes: notes, tags: tags) else { return }
        do {
            try SessionWriter.insert(finished, into: context)
            model.refreshDerivedState()
            dismiss()
        } catch {
            model.banner = Banner(message: String(localized: "Couldn't save the session. Try again."), isError: true)
        }
    }
}

private struct ManualSegmentRow: View {
    @Binding var segment: ManualSegment
    let items: [PracticeItem]

    var body: some View {
        VStack(alignment: .leading) {
            Picker("Item", selection: Binding(
                get: { segment.target.itemID },
                set: { id in
                    segment.target = id.flatMap { id in items.first { $0.id == id } }
                        .map { .item($0.id, title: $0.title) } ?? .general
                })) {
                Text("General practice").tag(UUID?.none)
                ForEach(items) { Text($0.title).tag(Optional($0.id)) }
            }
            Stepper(value: $segment.minutes, in: 0...ManualSessionBuilder.maxMinutes, step: 5) {
                Text("\(segment.minutes) min").monospacedDigit()
            }
        }
    }
}
