import PracticeKit
import SwiftData
import SwiftUI

/// Chromatic tuner, transposition-aware, with optional string-by-string mode.
struct TunerView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]
    @State private var instrumentID: UUID?
    @State private var stringMode = false
    @State private var tuningID: String?
    @State private var editingTunings = false

    private var tuner: TunerEngine { model.audio.tuner }

    private var instrument: Instrument? {
        let id = instrumentID ?? model.sessionController.active?.instrument?.id ?? settings.lastInstrumentID
        return instruments.first { $0.id == id } ?? instruments.first
    }

    /// Built-in tunings for this instrument plus the user's own.
    private var tunings: [StringTuning] {
        StringTuning.tunings(forPreset: instrument?.presetKey)
            + settings.customTunings.filter { $0.presetKey == nil || $0.presetKey == instrument?.presetKey }.map(\.asStringTuning)
    }

    private var selectedTuning: StringTuning? {
        tunings.first { $0.id == tuningID } ?? tunings.first
    }

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 24) {
            if let instrument, !instrument.hasPitch {
                ContentUnavailableView("No tuner for \(instrument.name)", systemImage: "tuningfork",
                                       description: Text("Pick a pitched instrument to tune."))
            } else if tuner.permissionDenied {
                ContentUnavailableView("Microphone access is off", systemImage: "mic.slash",
                                       description: Text("To tune, allow microphone access for Ostinato in Settings. Audio is analyzed live and never stored."))
            } else {
                NoteDisplay(reading: tuner.reading, written: !settings.showConcertPitch && (instrument?.transposition ?? 0) != 0)
                CentsNeedle(cents: tuner.reading?.cents)
                if stringMode, let tuning = selectedTuning {
                    StringTargets(tuning: tuning, reading: tuner.reading, transposition: instrument?.transposition ?? 0,
                                  written: !settings.showConcertPitch)
                }
            }
            Spacer(minLength: 0)
            Form {
                if instruments.count > 1 {
                    Picker("Instrument", selection: Binding(get: { instrument?.id }, set: { instrumentID = $0 })) {
                        ForEach(instruments) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if (instrument?.transposition ?? 0) != 0 {
                    Toggle("Show concert pitch", isOn: $settings.showConcertPitch)
                }
                if instrument?.hasPitch ?? true {
                    Toggle("String by string", isOn: $stringMode)
                    if stringMode {
                        Picker("Tuning", selection: Binding(get: { selectedTuning?.id }, set: { tuningID = $0 })) {
                            ForEach(tunings) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Button("Edit Tunings…") { editingTunings = true }
                    }
                }
                Stepper(value: $settings.a4Reference, in: NoteMath.a4Range, step: 1) {
                    Text("A4 = \(Int(settings.a4Reference)) Hz").monospacedDigit()
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxHeight: 260)
        }
        .padding(.top)
        .sheet(isPresented: $editingTunings) { TuningEditor(presetKey: instrument?.presetKey) }
        .navigationTitle("Tuner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: instrument?.id) {
            tuner.a4 = settings.a4Reference
            tuner.transposition = instrument?.transposition ?? 0
            if instrument?.hasPitch ?? true { await tuner.start() }
        }
        .onChange(of: settings.a4Reference) { _, value in tuner.a4 = value }
        .onDisappear { tuner.stop() }
    }
}

private struct NoteDisplay: View {
    let reading: NoteReading?
    let written: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reading?.name(written: written) ?? "–")
                    .font(.system(size: 96, weight: .semibold, design: .rounded))
                if let reading {
                    Text("\(reading.octave(written: written))").font(.title.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Text(reading.map { "\($0.cents >= 0 ? "+" : "")\(Int($0.cents.rounded())) cents" } ?? String(localized: "Play a note"))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.secondary)
            if let reading {
                Text("\(reading.frequency, format: .number.precision(.fractionLength(1))) Hz")
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.map {
            Text("\($0.name(written: written)) \($0.octave(written: written)), \(Int($0.cents.rounded())) cents \($0.cents >= 0 ? "sharp" : "flat")")
        } ?? Text("Listening"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// −50…+50 cents. In tune (±5) is shown with a label and shape, not color alone.
private struct CentsNeedle: View {
    let cents: Double?

    var body: some View {
        let value = max(-50, min(50, cents ?? 0))
        let inTune = cents.map { abs($0) <= 5 } ?? false
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack {
                    Capsule().fill(.fill.tertiary).frame(height: 6)
                    Rectangle().fill(.secondary).frame(width: 2, height: 28)
                    Capsule()
                        .fill(inTune ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                        .frame(width: inTune ? 10 : 6, height: 40)
                        .offset(x: CGFloat(value / 50) * (width / 2 - 8))
                        .opacity(cents == nil ? 0.2 : 1)
                        .animation(.smooth(duration: 0.15), value: value)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 44)
            HStack {
                Text("Flat"); Spacer()
                Label("In tune", systemImage: "checkmark.circle.fill").opacity(inTune ? 1 : 0)
                Spacer(); Text("Sharp")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .accessibilityHidden(true)
    }
}

private struct StringTargets: View {
    let tuning: StringTuning
    let reading: NoteReading?
    let transposition: Int
    let written: Bool

    var body: some View {
        let nearest = reading.map { tuning.nearestString(to: Double($0.concertMidi) + $0.cents / 100) } ?? nil
        HStack(spacing: 10) {
            ForEach(Array(tuning.strings.enumerated()), id: \.offset) { _, midi in
                let shown = written ? midi - transposition : midi
                Text("\(NoteMath.name(midi: shown))\(NoteMath.octave(midi: shown))")
                    .font(.headline)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(nearest == midi ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.fill.quaternary), in: .circle)
                    .accessibilityAddTraits(nearest == midi ? .isSelected : [])
            }
        }
    }
}

/// Add and remove custom tunings (e.g. DADGAD, open D, scordatura).
struct TuningEditor: View {
    let presetKey: String?
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""

    private var parsed: [Int]? { CustomTuning.parseNotes(notes) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. DADGAD)", text: $name)
                    TextField("Notes, lowest first (e.g. D2 A2 D3 G3 A3 D4)", text: $notes)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Add Tuning", systemImage: "plus") {
                        guard let strings = parsed else { return }
                        let title = name.trimmingCharacters(in: .whitespaces)
                        settings.customTunings.append(CustomTuning(
                            name: title.isEmpty ? notes : String(title.prefix(40)), strings: strings, presetKey: presetKey))
                        name = ""
                        notes = ""
                    }
                    .disabled(parsed == nil)
                } header: {
                    Text("New tuning")
                } footer: {
                    Text(notes.isEmpty || parsed != nil
                         ? "Use note names with octave numbers. Middle C is C4. Write the notes at concert pitch."
                         : "Couldn't read those notes. Try something like D2 A2 D3 G3 A3 D4.")
                }

                let mine = settings.customTunings.filter { $0.presetKey == nil || $0.presetKey == presetKey }
                if !mine.isEmpty {
                    Section("Your tunings") {
                        ForEach(mine) { tuning in
                            VStack(alignment: .leading) {
                                Text(tuning.name)
                                Text(tuning.notesText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { mine[$0].id }
                            settings.customTunings.removeAll { ids.contains($0.id) }
                        }
                    }
                }
            }
            .navigationTitle("Tunings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
