import PracticeKit
import SwiftData
import SwiftUI

/// Repertoire grouped by instrument, with search and filters. Two columns on iPad.
struct RepertoireView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Instrument.sortIndex) private var instruments: [Instrument]
    @Query(sort: [SortDescriptor(\PracticeItem.sortIndex), SortDescriptor(\PracticeItem.title)])
    private var items: [PracticeItem]

    @State private var selection: PracticeItem.ID?
    @State private var search = ""
    @State private var statusFilter: ItemStatus?
    @State private var categoryFilter: ItemCategory?
    @State private var showArchived = false
    @State private var editing: ItemEditorTarget?

    private var filtered: [PracticeItem] {
        items.filter { item in
            (showArchived || !item.isArchived)
                && (statusFilter == nil || item.status == statusFilter)
                && (categoryFilter == nil || item.category == categoryFilter)
                && (search.isEmpty || item.title.localizedStandardContains(search)
                    || (item.composer?.localizedStandardContains(search) ?? false))
        }
    }

    private var groups: [(id: String, title: String, items: [PracticeItem])] {
        let byInstrument = Dictionary(grouping: filtered) { $0.instrument?.id }
        var result = instruments.compactMap { instrument -> (String, String, [PracticeItem])? in
            guard let list = byInstrument[instrument.id], !list.isEmpty else { return nil }
            return (instrument.id.uuidString, instrument.name, list)
        }
        if let loose = byInstrument[nil], !loose.isEmpty {
            result.append(("none", String(localized: "No instrument"), loose))
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.id) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            NavigationLink(value: item.id) { ItemRow(item: item) }
                                .swipeActions(edge: .trailing) {
                                    Button(item.isArchived ? "Restore" : "Archive",
                                           systemImage: item.isArchived ? "arrow.uturn.backward" : "archivebox") {
                                        item.status = item.isArchived ? .learning : .archived
                                        try? context.save()
                                    }
                                    .tint(.indigo)
                                }
                        }
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    EmptyStateView(
                        title: "No repertoire yet",
                        message: "Add the pieces you're working on to track time per piece.",
                        systemImage: "music.note.list",
                        actionTitle: "Add Item") { editing = .new }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Pieces, exercises, composers")
            .navigationTitle("Repertoire")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Item", systemImage: "plus") { editing = .new }
                }
                ToolbarItem(placement: .secondaryAction) { filterMenu }
            }
        } detail: {
            if let id = selection, let item = items.first(where: { $0.id == id }) {
                ItemDetailView(item: item)
            } else {
                ContentUnavailableView("Choose an item", systemImage: "music.note",
                                       description: Text("See time spent, tempo progress and recordings."))
            }
        }
        .sheet(item: $editing) { target in
            ItemEditorView(item: target.item)
        }
        .task {
            if DemoScreen.has("-demoItem"), selection == nil {
                selection = items.first { $0.title.contains("Chaconne") }?.id
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $statusFilter) {
                Text("All statuses").tag(ItemStatus?.none)
                ForEach(ItemStatus.active) { Text($0.displayName).tag(Optional($0)) }
            }
            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(ItemCategory?.none)
                ForEach(ItemCategory.allCases) { Text($0.displayName).tag(Optional($0)) }
            }
            Toggle("Show Archived", isOn: $showArchived)
        } label: {
            Label("Filter", systemImage: statusFilter == nil && categoryFilter == nil
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }
}

enum ItemEditorTarget: Identifiable {
    case new
    case edit(PracticeItem)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let item): item.id.uuidString
        }
    }

    var item: PracticeItem? {
        if case .edit(let item) = self { return item }
        return nil
    }
}

struct ItemRow: View {
    let item: PracticeItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.symbolName)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(2)
                HStack(spacing: 6) {
                    if let composer = item.composer, !composer.isEmpty { Text(composer) }
                    Text(item.status.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DurationText.short(item.totalPracticed))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Create or edit an item.
struct ItemEditorView: View {
    let item: PracticeItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]

    @State private var title = ""
    @State private var composer = ""
    @State private var category: ItemCategory = .piece
    @State private var status: ItemStatus = .learning
    @State private var instrumentID: UUID?
    @State private var targetTempo: Int?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Composer (optional)", text: $composer)
                }
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(ItemCategory.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ItemStatus.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Instrument", selection: $instrumentID) {
                        Text("None").tag(UUID?.none)
                        ForEach(instruments) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section("Target tempo") {
                    Toggle("Set a target tempo", isOn: Binding(
                        get: { targetTempo != nil }, set: { targetTempo = $0 ? (targetTempo ?? 100) : nil }))
                    if let tempo = targetTempo {
                        Stepper(value: Binding(get: { tempo }, set: { targetTempo = $0 }), in: 20...300) {
                            Text("\(tempo) BPM").monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let item {
            title = item.title
            composer = item.composer ?? ""
            category = item.category
            status = item.status
            instrumentID = item.instrument?.id
            targetTempo = item.targetTempo
        } else {
            instrumentID = settings.lastInstrumentID ?? instruments.first?.id
        }
    }

    private func save() {
        let target = item ?? PracticeItem(title: "")
        if item == nil {
            target.sortIndex = (try? context.fetchCount(FetchDescriptor<PracticeItem>())) ?? 0
            context.insert(target)
        }
        target.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        let trimmedComposer = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        target.composer = trimmedComposer.isEmpty ? nil : trimmedComposer
        let categoryChanged = item != nil && target.category != category
        target.category = category
        target.status = status
        target.instrument = instruments.first { $0.id == instrumentID }
        target.targetTempo = targetTempo
        target.updatedAt = Date()
        try? context.save()
        if categoryChanged { model.storeDidChangeInBulk() }
        dismiss()
    }
}
