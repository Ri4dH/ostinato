import PracticeKit
import SwiftData
import SwiftUI

/// Home: start in ≤ 2 taps, see today at a glance, jump back into recent items.
struct PracticeHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]

    @State private var selectedInstrumentID: UUID?
    @State private var showingManualLog = false
    @State private var showingInstrumentPicker = false
    @State private var tool: PracticeTool?
    @State private var startTrigger = 0

    private var selectedInstrument: Instrument? {
        let id = selectedInstrumentID ?? settings.lastInstrumentID
        return instruments.first { $0.id == id } ?? instruments.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let active = model.sessionController.active {
                        ActiveSessionCard(session: active) { model.isShowingActiveSession = true }
                    } else {
                        startSection
                    }
                    TodaySummaryCard(snapshot: model.snapshot, goal: settings.goal)
                    ContinueWithSection { item in
                        startTrigger += 1
                        model.startSession(instrument: item.instrument ?? selectedInstrument, item: item)
                    }
                    toolsSection
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Log Past Session", systemImage: "plus.circle") { showingManualLog = true }
                }
            }
            .sheet(isPresented: $showingManualLog) { ManualLogView() }
            .sheet(isPresented: $showingInstrumentPicker) {
                InstrumentQuickPicker(selection: $selectedInstrumentID)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $tool) { tool in
                NavigationStack { tool.destination }
            }
            .sensoryFeedback(.start, trigger: startTrigger)
        }
    }

    private var startSection: some View {
        VStack(spacing: 12) {
            Button {
                startTrigger += 1
                model.startSession(instrument: selectedInstrument)
            } label: {
                Label("Start Practice", systemImage: "play.fill")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("startPractice")

            if instruments.count > 1, let instrument = selectedInstrument {
                Button {
                    showingInstrumentPicker = true
                } label: {
                    HStack(spacing: 8) {
                        InstrumentIcon(instrument, size: 24)
                        Text(instrument.name)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Instrument: \(instrument.name)")
                .accessibilityHint("Choose a different instrument")
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tools").font(.headline)
            HStack(spacing: 12) {
                ForEach(PracticeTool.allCases) { tool in
                    Button {
                        self.tool = tool
                    } label: {
                        Label(tool.title, systemImage: tool.symbol)
                            .labelStyle(.verticalTool)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }
}

enum PracticeTool: String, CaseIterable, Identifiable {
    case metronome, tuner, drone
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .metronome: "Metronome"
        case .tuner: "Tuner"
        case .drone: "Drone"
        }
    }

    var symbol: String {
        switch self {
        case .metronome: "metronome"
        case .tuner: "tuningfork"
        case .drone: "waveform"
        }
    }

    @MainActor @ViewBuilder var destination: some View {
        switch self {
        case .metronome: MetronomeView()
        case .tuner: TunerView()
        case .drone: DroneView()
        }
    }
}

struct VerticalToolLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title2)
            configuration.title
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

extension LabelStyle where Self == VerticalToolLabelStyle {
    static var verticalTool: VerticalToolLabelStyle { VerticalToolLabelStyle() }
}

/// Shown on Home while a session is running.
struct ActiveSessionCard: View {
    let session: ActiveSession
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "waveform")
                    .font(.title)
                    .symbolEffect(.variableColor.iterative, isActive: !session.isPaused)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.isPaused ? "Paused" : "Practicing").font(.subheadline).foregroundStyle(.secondary)
                    Text(session.currentTarget.title ?? String(localized: "General practice"))
                        .font(.headline)
                        .lineLimit(2)
                }
                Spacer()
                SessionTimerText(session: session)
                    .font(.title2.bold())
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.glassProminent)
        .accessibilityHint("Opens the running session")
    }
}

/// Today vs goal, plus the streak.
struct TodaySummaryCard: View {
    let snapshot: WidgetSnapshot?
    let goal: GoalSettings
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minutes = snapshot?.todayMinutes(now: context.date, calendar: .current, active: model.sessionController.active) ?? 0
            let progress = goal.dailyMinutes > 0 ? Double(minutes) / Double(goal.dailyMinutes) : 0
            HStack(spacing: 20) {
                GoalRing(progress: progress, lineWidth: 12)
                    .frame(width: 84, height: 84)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(minutes) of \(goal.dailyMinutes) min")
                        .font(.title2.bold())
                        .monospacedDigit()
                    if let streak = snapshot?.streak, streak > 0 {
                        Label("\(streak)-day streak", systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Start a session to begin a streak.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(.fill.quinary, in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Continue with…" chips: the most recently practiced items.
struct ContinueWithSection: View {
    let start: (PracticeItem) -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @State private var items: [PracticeItem] = []

    var body: some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Continue with").font(.headline)
                    FlowLayout(spacing: 8) {
                        ForEach(items) { item in
                            Button {
                                start(item)
                            } label: {
                                Label(item.title, systemImage: item.category.symbolName)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                                    .frame(minHeight: 36)
                            }
                            .buttonStyle(.glass)
                            .accessibilityHint("Starts a session on this item")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: model.snapshot?.updatedAt) {
            items = RecentItems.fetch(in: context, instrumentID: nil, limit: 5)
        }
    }
}

/// Picks the instrument for the next session.
struct InstrumentQuickPicker: View {
    @Binding var selection: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Instrument> { !$0.isArchived }, sort: \Instrument.sortIndex)
    private var instruments: [Instrument]

    var body: some View {
        NavigationStack {
            List(instruments) { instrument in
                Button {
                    selection = instrument.id
                    settings.lastInstrumentID = instrument.id
                    dismiss()
                } label: {
                    HStack {
                        InstrumentIcon(instrument)
                        Text(instrument.name).foregroundStyle(.primary)
                        Spacer()
                        if instrument.id == (selection ?? settings.lastInstrumentID) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
                .tint(.primary)
                .accessibilityAddTraits(instrument.id == (selection ?? settings.lastInstrumentID) ? .isSelected : [])
            }
            .navigationTitle("Instrument")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
