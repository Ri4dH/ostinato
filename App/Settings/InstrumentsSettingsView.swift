import PracticeKit
import SwiftData
import SwiftUI

/// Add, edit, reorder and archive instruments. Unlimited and free.
struct InstrumentsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Instrument.sortIndex) private var instruments: [Instrument]
    @State private var adding = false
    @State private var editing: Instrument?

    var body: some View {
        List {
            Section {
                ForEach(instruments.filter { !$0.isArchived }) { instrument in
                    Button { editing = instrument } label: {
                        HStack {
                            InstrumentIcon(instrument)
                            Text(instrument.name).foregroundStyle(.primary)
                        }
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("Archive", systemImage: "archivebox") { instrument.isArchived = true; try? context.save() }
                            .tint(.indigo)
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("Archived instruments keep their history.")
            }
            let archived = instruments.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { instrument in
                        HStack {
                            InstrumentIcon(instrument)
                            Text(instrument.name)
                            Spacer()
                            Button("Restore") { instrument.isArchived = false; try? context.save() }
                        }
                    }
                }
            }
        }
        .navigationTitle("Instruments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Add Instrument", systemImage: "plus") { adding = true } }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                InstrumentPresetPicker(selected: .constant([])) { preset in
                    let instrument = preset.map { Instrument(preset: $0, sortIndex: instruments.count) }
                        ?? Instrument(name: String(localized: "My instrument"), sortIndex: instruments.count)
                    context.insert(instrument)
                    try? context.save()
                    adding = false
                    if preset == nil { editing = instrument }
                }
                .navigationTitle("Add Instrument")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } } }
            }
        }
        .sheet(item: $editing) { InstrumentEditor(instrument: $0) }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var active = instruments.filter { !$0.isArchived }
        active.move(fromOffsets: source, toOffset: destination)
        for (index, instrument) in active.enumerated() { instrument.sortIndex = index }
        try? context.save()
    }
}

/// Grouped preset list. With `onPick`, tapping adds one; otherwise multi-select (onboarding).
struct InstrumentPresetPicker: View {
    @Binding var selected: Set<String>
    var onPick: ((InstrumentPreset?) -> Void)?
    @State private var search = ""

    var body: some View {
        List {
            if onPick != nil {
                Button { onPick?(nil) } label: { Label("Custom instrument", systemImage: "plus.circle") }
            }
            ForEach(InstrumentGroup.allCases) { group in
                let presets = InstrumentPreset.presets(in: group).filter { search.isEmpty || $0.name.localizedStandardContains(search) }
                if !presets.isEmpty {
                    Section(group.displayName) {
                        ForEach(presets) { preset in
                            Button {
                                if let onPick { onPick(preset) } else if selected.contains(preset.key) {
                                    selected.remove(preset.key)
                                } else {
                                    selected.insert(preset.key)
                                }
                            } label: {
                                HStack {
                                    InstrumentIcon(symbolName: preset.symbolName, colorHex: preset.colorHex, size: 30)
                                    Text(preset.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selected.contains(preset.key) {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                    }
                                }
                            }
                            .tint(.primary)
                            .accessibilityAddTraits(selected.contains(preset.key) ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find an instrument")
    }
}

/// Name, icon, color and transposition.
struct InstrumentEditor: View {
    @Bindable var instrument: Instrument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let symbols = ["pianokeys", "pianokeys.inverse", "guitars", "guitars.fill", "music.quarternote.3", "wind",
                           "horn", "horn.blast", "metronome", "music.mic", "ear", "book.closed", "music.note.list",
                           "hand.wave", "hand.raised", "music.note"]

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Name", text: $instrument.name) }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(InstrumentPalette.colors) { swatch in
                            Button { instrument.colorHex = swatch.hex } label: {
                                Circle().fill(Color(hex: swatch.hex)).frame(width: 36, height: 36)
                                    .overlay {
                                        if instrument.colorHex.caseInsensitiveCompare(swatch.hex) == .orderedSame {
                                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(swatch.name)
                            .accessibilityAddTraits(instrument.colorHex == swatch.hex ? .isSelected : [])
                        }
                    }
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))], spacing: 12) {
                        ForEach(symbols, id: \.self) { symbol in
                            Button { instrument.symbolName = symbol } label: {
                                InstrumentIcon(symbolName: symbol,
                                               colorHex: instrument.symbolName == symbol ? instrument.colorHex : "#8E8E93", size: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(instrument.symbolName == symbol ? .isSelected : [])
                        }
                    }
                }
                Section {
                    Stepper(value: $instrument.transposition, in: -24...24) {
                        LabeledContent("Transposition", value: instrument.transposition == 0
                                       ? String(localized: "Concert pitch")
                                       : String(localized: "\(instrument.transposition) semitones"))
                    }
                } footer: {
                    Text("Used by the tuner and drone to show written notes. B♭ clarinet is −2, alto sax is −9, F horn is −7.")
                }
            }
            .navigationTitle(instrument.name.isEmpty ? String(localized: "Instrument") : instrument.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if instrument.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            instrument.name = String(localized: "My instrument")
                        }
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}
