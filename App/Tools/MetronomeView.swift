import PracticeKit
import SwiftData
import SwiftUI

/// Full-screen metronome, or a compact panel inside a session.
struct MetronomeView: View {
    var compact = false
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var tapper = TapTempo()
    @State private var savedTrigger = 0
    @State private var customSignature = false

    private var engine: MetronomeEngine { model.audio.metronome }

    var body: some View {
        @Bindable var engine = engine
        ScrollView {
            VStack(spacing: compact ? 16 : 28) {
                BeatIndicator(engine: engine)

                VStack(spacing: 4) {
                    Text("\(engine.settings.bpm)")
                        .font(.system(size: compact ? 64 : 96, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("BPM").font(.headline).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tempo")
                .accessibilityValue("\(engine.settings.bpm) beats per minute")
                .accessibilityAdjustableAction { direction in
                    engine.settings.bpm += direction == .increment ? 1 : -1
                }

                HStack(spacing: 12) {
                    nudge(-5); nudge(-1)
                    Slider(value: Binding(get: { Double(engine.settings.bpm) }, set: { engine.settings.bpm = Int($0) }),
                           in: 20...300, step: 1) { Text("Tempo") }
                    nudge(1); nudge(5)
                }

                HStack(spacing: 12) {
                    Button {
                        engine.toggle()
                    } label: {
                        Label(engine.isRunning ? "Stop" : "Start", systemImage: engine.isRunning ? "stop.fill" : "play.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        if let bpm = tapper.tap(at: ProcessInfo.processInfo.systemUptime) { engine.settings.bpm = bpm }
                    } label: {
                        Text("Tap").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("Tap repeatedly in time to set the tempo")
                }

                options(engine: engine)

                if let item = currentItem {
                    Button {
                        context.insert(item.logTempo(engine.settings.bpm, source: .metronome))
                        try? context.save()
                        savedTrigger += 1
                    } label: {
                        Label("Save \(engine.settings.bpm) BPM to \(item.title)", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding()
        }
        .navigationTitle("Metronome")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onChange(of: engine.settings) { _, new in settings.metronome = new }
        .sensoryFeedback(.success, trigger: savedTrigger)
        .alert("Couldn't start the metronome", isPresented: Binding(
            get: { engine.lastError != nil }, set: { if !$0 { engine.lastError = nil } })) {
            Button("OK") {}
        } message: { Text(engine.lastError ?? "") }
    }

    private var currentItem: PracticeItem? {
        model.sessionController.active?.currentTarget.itemID.flatMap { try? SessionWriter.fetchItem(id: $0, in: context) }
    }

    private func nudge(_ amount: Int) -> some View {
        Button(amount > 0 ? "+\(amount)" : "\(amount)") { engine.settings.bpm += amount }
            .buttonStyle(.glass)
            .monospacedDigit()
            .accessibilityLabel(amount > 0 ? "Faster by \(amount)" : "Slower by \(-amount)")
    }

    @ViewBuilder private func options(engine: MetronomeEngine) -> some View {
        @Bindable var engine = engine
        VStack(spacing: 14) {
            Picker("Time signature", selection: Binding(
                get: { "\(engine.settings.beatsPerBar)/\(engine.settings.beatUnit)" },
                set: { value in
                    let parts = value.split(separator: "/").compactMap { Int($0) }
                    if parts.count == 2 { engine.settings.beatsPerBar = parts[0]; engine.settings.beatUnit = parts[1] }
                })) {
                ForEach(MetronomeSettings.commonSignatures, id: \.0) { sig in
                    Text("\(sig.0)/\(sig.1)").tag("\(sig.0)/\(sig.1)")
                }
                if !MetronomeSettings.commonSignatures.contains(where: { $0 == (engine.settings.beatsPerBar, engine.settings.beatUnit) }) {
                    Text("\(engine.settings.beatsPerBar)/\(engine.settings.beatUnit)")
                        .tag("\(engine.settings.beatsPerBar)/\(engine.settings.beatUnit)")
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureGroup("Custom time signature", isExpanded: $customSignature) {
                Stepper("Beats per bar: \(engine.settings.beatsPerBar)", value: $engine.settings.beatsPerBar, in: 1...16)
                Picker("Beat unit", selection: $engine.settings.beatUnit) {
                    Text("Quarter").tag(4)
                    Text("Eighth").tag(8)
                }
                .pickerStyle(.segmented)
            }

            Picker("Subdivision", selection: $engine.settings.subdivision) {
                ForEach(Subdivision.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Toggle("Accent first beat", isOn: $engine.settings.accentFirstBeat)

            HStack {
                Image(systemName: "speaker.fill").accessibilityHidden(true)
                Slider(value: $engine.settings.volume, in: 0...1) { Text("Volume") }
                Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
            }
        }
    }
}

/// Visual pulse for the current beat (respects Reduce Motion).
struct BeatIndicator: View {
    let engine: MetronomeEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !engine.isRunning)) { _ in
            let beat = engine.currentBeat()
            HStack(spacing: 8) {
                ForEach(0..<engine.settings.beatsPerBar, id: \.self) { index in
                    Circle()
                        .fill(beat == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary))
                        .frame(width: index == 0 ? 18 : 14, height: index == 0 ? 18 : 14)
                        .scaleEffect(beat == index && !reduceMotion ? 1.25 : 1)
                }
            }
            .frame(height: 24)
        }
        .accessibilityHidden(true)
    }
}
