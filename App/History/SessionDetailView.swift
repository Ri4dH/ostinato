import PracticeKit
import SwiftData
import SwiftUI

/// Everything about a saved session, all editable.
struct SessionDetailView: View {
    @Bindable var session: PracticeSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]
    @Query(filter: #Predicate<PracticeItem> { $0.statusRaw != "archived" }, sort: \PracticeItem.title)
    private var items: [PracticeItem]
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Total") {
                    Text(DurationText.short(session.activeDuration)).font(.headline.monospacedDigit())
                }
                DatePicker("Started", selection: $session.startDate)
                Picker("Instrument", selection: Binding(
                    get: { session.instrument?.id },
                    set: { id in session.instrument = instruments.first { $0.id == id } })) {
                    Text("None").tag(UUID?.none)
                    ForEach(instruments) { Text($0.name).tag(Optional($0.id)) }
                }
                if session.source != .phone {
                    LabeledContent("Logged from", value: sourceName)
                }
            }

            Section("Time per item") {
                ForEach(session.sortedSegments) { segment in
                    SavedSegmentEditor(segment: segment, items: items) { session.recomputeDuration() }
                }
                .onDelete(perform: deleteSegments)
                Button("Add Item", systemImage: "plus", action: addSegment)
            }

            Section("How did it go?") {
                RatingPicker(title: "Session", symbol: "star", value: $session.rating)
                RatingPicker(title: "Focus", symbol: "circle", value: $session.focus)
            }

            Section("Notes") {
                TextField("Notes", text: $session.notes, axis: .vertical)
                    .lineLimit(3...12)
                    .accessibilityIdentifier("sessionNotes")
            }

            Section("Tags") { TagEditor(tags: $session.tags) }

            if let recordings = session.recordings, !recordings.isEmpty {
                RecordingsSection(recordings: recordings.sorted { $0.createdAt < $1.createdAt })
            }

            Section {
                Button("Delete Session", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(Text(session.startDate, format: .dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            session.tags = SessionWriter.normalizedTags(session.tags)
            try? context.save()
            model.refreshDerivedState()
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                context.delete(session)
                try? context.save()
                model.refreshDerivedState()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(DurationText.spoken(session.activeDuration)) will be removed from your stats. Recordings are kept.")
        }
    }

    private var sourceName: String {
        switch session.source {
        case .phone: String(localized: "iPhone")
        case .watch: String(localized: "Apple Watch")
        case .manual: String(localized: "Manual entry")
        case .siri: String(localized: "Siri or Shortcuts")
        }
    }

    private func deleteSegments(_ offsets: IndexSet) {
        let sorted = session.sortedSegments
        for index in offsets { context.delete(sorted[index]) }
        session.segments = (session.segments ?? []).filter { segment in !offsets.contains { sorted[$0].id == segment.id } }
        session.recomputeDuration()
        try? context.save()
    }

    private func addSegment() {
        let last = session.sortedSegments.last
        let start = last?.endDate ?? session.endDate ?? session.startDate
        let segment = SessionSegment(startDate: start, endDate: start.addingTimeInterval(600), activeDuration: 600,
                                     sortIndex: (last?.sortIndex ?? -1) + 1)
        context.insert(segment)
        session.segments = (session.segments ?? []) + [segment]
        session.recomputeDuration()
        try? context.save()
    }
}

private struct SavedSegmentEditor: View {
    @Bindable var segment: SessionSegment
    let items: [PracticeItem]
    let changed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Item", selection: Binding(
                get: { segment.item?.id },
                set: { id in segment.item = items.first { $0.id == id } })) {
                Text(segment.label ?? String(localized: "General practice")).tag(UUID?.none)
                ForEach(items) { Text($0.title).tag(Optional($0.id)) }
            }
            if segment.item == nil {
                TextField("Label", text: Binding(get: { segment.label ?? "" },
                                                 set: { segment.label = $0.isEmpty ? nil : String($0.prefix(200)) }))
                    .font(.subheadline)
            }
            Stepper(value: Binding(
                get: { Int((segment.activeDuration / 60).rounded()) },
                set: { segment.activeDuration = TimeInterval(max(0, $0) * 60); changed() }),
                    in: 0...ManualSessionBuilder.maxMinutes) {
                Text(DurationText.short(segment.activeDuration)).monospacedDigit()
            }
        }
    }
}
