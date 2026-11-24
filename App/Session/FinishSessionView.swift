import PracticeKit
import SwiftData
import SwiftUI

/// Review and save: segment breakdown (editable), rating, focus, notes, tags.
struct FinishSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FinishedSession
    @State private var editingSegment: FinishedSegment?
    @State private var confirmingDiscard = false
    @State private var saveTrigger = 0

    init(draft: FinishedSession) {
        // One-time seed: the sheet owns its editable copy.
        _draft = State(initialValue: draft)
    }

    private var total: TimeInterval { draft.segments.reduce(0) { $0 + $1.activeDuration } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Total") {
                        Text(DurationText.short(total)).font(.title2.bold()).monospacedDigit()
                    }
                    .accessibilityValue(DurationText.spoken(total))
                }

                Section {
                    ForEach(draft.segments) { segment in
                        SegmentRow(segment: segment) { editingSegment = segment }
                    }
                    .onDelete { draft.segments.remove(atOffsets: $0) }
                } header: {
                    Text("Time per item")
                } footer: {
                    if draft.segments.isEmpty { Text("All segments removed. The session will be saved with no time.") }
                }

                Section("How did it go?") {
                    RatingPicker(title: "Session", symbol: "star", value: $draft.rating)
                    RatingPicker(title: "Focus", symbol: "circle", value: $draft.focus)
                }

                Section("Notes") {
                    TextField("What worked, what to try next time", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Tags") {
                    TagEditor(tags: $draft.tags)
                }

                Section {
                    Button("Discard Session", role: .destructive) { confirmingDiscard = true }
                }
            }
            .navigationTitle("Finish Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep Practicing") {
                        model.finishDraft = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTrigger += 1
                        draft.activeDuration = total
                        model.save(draft)
                    }
                    .bold()
                    .accessibilityIdentifier("saveSession")
                }
            }
            .sheet(item: $editingSegment) { segment in
                SegmentEditor(segment: segment) { updated in
                    if let index = draft.segments.firstIndex(where: { $0.id == updated.id }) {
                        draft.segments[index] = updated
                    }
                }
            }
            .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Session", role: .destructive) { model.discardActiveSession() }
                Button("Keep Session", role: .cancel) {}
            } message: {
                Text("\(DurationText.spoken(total)) of practice won't be saved.")
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
        }
    }
}

private struct SegmentRow: View {
    let segment: FinishedSegment
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack {
                VStack(alignment: .leading) {
                    Text(segment.target.title ?? String(localized: "General practice"))
                        .foregroundStyle(.primary)
                    Text(segment.startDate, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(DurationText.short(segment.activeDuration))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.primary)
        .accessibilityHint("Edit this segment")
    }
}

/// Rename, reassign or adjust one segment.
struct SegmentEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<PracticeItem> { $0.statusRaw != "archived" }, sort: \PracticeItem.title)
    private var items: [PracticeItem]
    @State private var segment: FinishedSegment
    @State private var minutes: Int
    @State private var label: String
    let onSave: (FinishedSegment) -> Void

    init(segment: FinishedSegment, onSave: @escaping (FinishedSegment) -> Void) {
        _segment = State(initialValue: segment)
        _minutes = State(initialValue: max(0, Int((segment.activeDuration / 60).rounded())))
        _label = State(initialValue: segment.target.itemID == nil ? (segment.target.title ?? "") : "")
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    Picker("Item", selection: $segment.target.itemID) {
                        Text("None").tag(UUID?.none)
                        ForEach(items) { item in Text(item.title).tag(Optional(item.id)) }
                    }
                    if segment.target.itemID == nil {
                        TextField("Label (e.g. Warm-up)", text: $label)
                    }
                }
                Section("Time") {
                    Stepper(value: $minutes, in: 0...ManualSessionBuilder.maxMinutes) {
                        Text("\(minutes) min").monospacedDigit()
                    }
                }
            }
            .navigationTitle("Edit Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let id = segment.target.itemID {
                            segment.target.title = items.first { $0.id == id }?.title
                        } else {
                            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                            segment.target.title = trimmed.isEmpty ? nil : trimmed
                        }
                        // Keep seconds precision unless the minutes were changed.
                        if minutes != Int((segment.activeDuration / 60).rounded()) {
                            segment.activeDuration = TimeInterval(minutes * 60)
                        }
                        onSave(segment)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Multi-select of existing tags plus creating new ones.
struct TagEditor: View {
    @Binding var tags: [String]
    @Environment(\.modelContext) private var context
    @State private var known: [String] = []
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    TagChip(text: tag, isSelected: tags.contains(tag)) { toggle(tag) }
                }
            }
            HStack {
                TextField("New tag", text: $newTag)
                    .onSubmit(add)
                    .submitLabel(.done)
                Button("Add", action: add).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task { known = Self.recentTags(in: context) }
    }

    private var allTags: [String] {
        var seen = Set<String>()
        return (tags + known).filter { seen.insert($0.lowercased()).inserted }
    }

    private func toggle(_ tag: String) {
        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) } else { tags.append(tag) }
    }

    private func add() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        newTag = ""
        guard !tag.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) { tags.append(tag) }
    }

    static func recentTags(in context: ModelContext) -> [String] {
        var descriptor = FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 300
        let sessions = (try? context.fetch(descriptor)) ?? []
        var counts: [String: Int] = [:]
        for tag in sessions.flatMap(\.tags) { counts[tag, default: 0] += 1 }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(20).map(\.key)
    }
}
