import PracticeKit
import SwiftData
import SwiftUI

/// The running session. Readable from a music stand: huge timer, big targets.
struct ActiveSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panel: SessionPanel?
    @State private var showingNote = false
    @State private var switchTrigger = 0

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if let session = model.sessionController.active {
                    content(session)
                } else {
                    ContentUnavailableView("No session running", systemImage: "music.note",
                                           description: Text("Start a session from the Practice tab."))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Minimize", systemImage: "chevron.down") { model.isShowingActiveSession = false }
                        .accessibilityHint("The session keeps running")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color(hex: model.sessionController.active?.instrument?.colorHex ?? InstrumentPalette.defaultHex))
        .sheet(item: $model.finishDraft) { draft in
            FinishSessionView(draft: draft)
                .interactiveDismissDisabled()
        }
        .sheet(item: $panel) { panel in
            NavigationStack { panel.content }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .sheet(isPresented: $showingNote) {
            QuickNoteSheet().presentationDetents([.height(260)])
        }
        .sessionConflictAlert()
        .bannerOverlay($model.banner)
        .sensoryFeedback(.selection, trigger: switchTrigger)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private func content(_ session: ActiveSession) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                header(session)
                TimerDisplay(session: session)
                ItemSwitcher(session: session) { switchTrigger += 1 }
                if model.audio.recorder.isRecording { RecordingIndicator() }
                SessionControls(session: session, panel: $panel, showingNote: $showingNote)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func header(_ session: ActiveSession) -> some View {
        HStack(spacing: 10) {
            if let instrument = session.instrument {
                InstrumentIcon(symbolName: instrument.symbolName, colorHex: instrument.colorHex, size: 28)
                Text(instrument.name).font(.headline)
            }
            Spacer()
            if session.isPaused {
                Label {
                    Text("Paused").foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "pause.fill").foregroundStyle(.orange)
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.orange.opacity(0.18), in: .capsule)
            }
        }
    }
}

/// Total timer (≥ 72 pt) plus the current item and its own timer. One
/// timeline drives both so they always tick together.
struct TimerDisplay: View {
    let session: ActiveSession
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 88

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: session.isPaused)) { context in
            let total = session.elapsed(at: context.date)
            let segment = session.currentSegmentElapsed(at: context.date)
            let title = session.currentTarget.title ?? String(localized: "General practice")
            VStack(spacing: 8) {
                Text(DurationText.clock(total))
                    .font(.system(size: max(72, timerSize), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .opacity(session.isPaused ? 0.5 : 1)
                    .accessibilityLabel("Total time")
                    .accessibilityValue(DurationText.timerSpoken(total))
                    .accessibilityIdentifier("sessionTimer")

                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .accessibilityLabel("Current item: \(title)")

                Label(DurationText.clock(segment), systemImage: "stopwatch")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Time on this item")
                    .accessibilityValue(DurationText.timerSpoken(segment))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

/// One-tap switching between items, plus inline "New item".
struct ItemSwitcher: View {
    let session: ActiveSession
    let didSwitch: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PracticeItem> { $0.statusRaw != "archived" }, sort: \PracticeItem.updatedAt, order: .reverse)
    private var allItems: [PracticeItem]
    @State private var newItemTitle = ""
    @State private var addingItem = false

    private var items: [PracticeItem] {
        let instrumentID = session.instrument?.id
        let recent = Set(session.recentItemIDs)
        return allItems
            .filter { instrumentID == nil || $0.instrument == nil || $0.instrument?.id == instrumentID }
            .sorted { (recent.contains($0.id) ? 0 : 1, $0.sortIndex) < (recent.contains($1.id) ? 0 : 1, $1.sortIndex) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Working on").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    chip(title: String(localized: "General"), symbol: "music.note", isCurrent: session.currentTarget.itemID == nil) {
                        model.switchTo(nil)
                        didSwitch()
                    }
                    ForEach(items) { item in
                        chip(title: item.title, symbol: item.category.symbolName,
                             isCurrent: session.currentTarget.itemID == item.id) {
                            model.switchTo(item)
                            didSwitch()
                        }
                    }
                    Button {
                        addingItem = true
                    } label: {
                        Label("New Item", systemImage: "plus")
                            .frame(minHeight: 52)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
        .alert("New item", isPresented: $addingItem) {
            TextField("Title", text: $newItemTitle)
            Button("Add and Switch") { addItem() }
            Button("Cancel", role: .cancel) { newItemTitle = "" }
        } message: {
            Text("A piece, exercise or scale to track time on.")
        }
    }

    private func chip(title: String, symbol: String, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .lineLimit(1)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(minHeight: 52)
                .padding(.horizontal, 6)
        }
        .buttonStyle(isCurrent ? AnyButtonStyle(.glassProminent) : AnyButtonStyle(.glass))
        .tint(isCurrent ? nil : Color.primary)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func addItem() {
        let title = newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        newItemTitle = ""
        guard !title.isEmpty else { return }
        let instrument = session.instrument.flatMap { try? SessionWriter.fetchInstrument(id: $0.id, in: context) }
        let item = PracticeItem(title: title, instrument: instrument)
        context.insert(item)
        try? context.save()
        model.switchTo(item)
        didSwitch()
    }
}

/// Type-erased button style so selected/unselected chips can differ.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Pause/Resume, Record, Metronome, Note, Finish.
struct SessionControls: View {
    let session: ActiveSession
    @Binding var panel: SessionPanel?
    @Binding var showingNote: Bool
    @Environment(AppModel.self) private var model
    @State private var pauseTrigger = 0
    @State private var confirmDiscard = false
    @ScaledMetric(relativeTo: .caption) private var toolWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    pauseTrigger += 1
                    model.sessionController.togglePause()
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("pauseResume")

                Button {
                    model.beginFinish()
                } label: {
                    Label("Finish", systemImage: "checkmark")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("finishSession")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: toolWidth), spacing: 12)], spacing: 12) {
                toolButton(model.audio.recorder.isRecording ? "Stop" : "Record",
                           symbol: model.audio.recorder.isRecording ? "stop.circle.fill" : "record.circle") {
                    if model.audio.recorder.isRecording { model.audio.recorder.stop() } else { model.startRecording() }
                }
                .foregroundStyle(model.audio.recorder.isRecording ? .red : .primary)
                toolButton("Metronome", symbol: "metronome") { panel = .metronome }
                toolButton("Tuner", symbol: "tuningfork") { panel = .tuner }
                toolButton("Drone", symbol: "waveform") { panel = .drone }
                toolButton("Note", symbol: "square.and.pencil") { showingNote = true }
            }

            Button("Discard Session", role: .destructive) { confirmDiscard = true }
                .font(.subheadline)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .sensoryFeedback(.impact, trigger: pauseTrigger)
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Session", role: .destructive) { model.discardActiveSession() }
            Button("Keep Practicing", role: .cancel) {}
        } message: {
            Text("The time from this session won't be saved. Recordings are kept.")
        }
        .alert("Microphone access is off", isPresented: Binding(
            get: { model.audio.recorder.permissionDenied },
            set: { model.audio.recorder.permissionDenied = $0 })) {
            Button("OK") {}
        } message: {
            Text("To record, allow microphone access for Ostinato in Settings.")
        }
    }

    private func toolButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.verticalTool)
                .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.glass)
        .tint(.primary)
    }
}

enum SessionPanel: String, Identifiable {
    case metronome, tuner, drone
    var id: String { rawValue }

    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .metronome: MetronomeView(compact: true)
        case .tuner: TunerView()
        case .drone: DroneView()
        }
    }
}

/// Level meter and elapsed time while recording.
struct RecordingIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            let level = model.audio.recorder.level()
            HStack(spacing: 12) {
                Circle().fill(.red).frame(width: 10, height: 10)
                Text(DurationText.clock(model.audio.recorder.elapsed)).monospacedDigit()
                GeometryReader { proxy in
                    Capsule().fill(.fill.tertiary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.red.gradient).frame(width: proxy.size.width * CGFloat(level))
                        }
                }
                .frame(height: 8)
            }
            .padding()
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording")
            .accessibilityValue(DurationText.timerSpoken(model.audio.recorder.elapsed))
        }
    }
}

/// A note typed during the session; added to the session notes.
struct QuickNoteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("What did you notice?", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .focused($focused)
                .padding()
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            model.sessionController.addNote(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
    }
}
