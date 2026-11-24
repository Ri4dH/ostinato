import PracticeKit
import SwiftUI

@main
struct OstinatoWatchApp: App {
    @State private var model = WatchModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if model.controller.active != nil {
                    WatchActiveView()
                } else {
                    WatchHomeView()
                }
            }
            .environment(model)
            .task { model.activate() }
            .sheet(item: $model.finishing) { WatchFinishView(draft: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.controller.reloadFromDisk() }
        }
    }
}

struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model
    @State private var startTrigger = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let minutes = model.todayMinutes(at: context.date)
                    let goal = model.context.goal.dailyMinutes
                    Gauge(value: Double(min(minutes, goal)), in: 0...Double(max(goal, 1))) {
                        Text("min")
                    } currentValueLabel: {
                        Text("\(minutes)")
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(.blue)
                    .accessibilityLabel("Today: \(minutes) of \(goal) minutes")
                }
                if model.context.streak > 0 {
                    Label("\(model.context.streak)-day streak", systemImage: "flame.fill")
                        .font(.footnote).foregroundStyle(.orange)
                }

                Button {
                    startTrigger += 1
                    model.start(instrument: model.lastInstrument)
                } label: {
                    Label("Start", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: model.lastInstrument?.colorHex ?? InstrumentPalette.defaultHex))

                if model.instruments.count > 1 {
                    NavigationLink {
                        List(model.instruments, id: \.id) { instrument in
                            Button {
                                startTrigger += 1
                                model.start(instrument: instrument)
                            } label: {
                                Label(instrument.name, systemImage: instrument.symbolName)
                                    .foregroundStyle(Color(hex: instrument.colorHex))
                            }
                        }
                        .navigationTitle("Instrument")
                    } label: {
                        Label(model.lastInstrument?.name ?? String(localized: "Instrument"), systemImage: "chevron.right")
                    }
                }

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Interval taps", systemImage: "bell")
                }
                if !model.pendingOutbox.isEmpty {
                    Label("\(model.pendingOutbox.count) waiting for iPhone", systemImage: "iphone.and.arrow.forward")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ostinato")
        .sensoryFeedback(.start, trigger: startTrigger)
    }
}

struct WatchActiveView: View {
    @Environment(WatchModel.self) private var model
    @State private var switchTrigger = 0

    var body: some View {
        if let session = model.controller.active {
            let tint = Color(hex: session.instrument?.colorHex ?? InstrumentPalette.defaultHex)
            ScrollView {
                VStack(spacing: 8) {
                    Text(timerInterval: session.timerReferenceDate(at: .now)...Date.distantFuture,
                         pauseTime: session.isPaused ? .now : nil, countsDown: false)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(session.isPaused ? .secondary : .primary)
                        .accessibilityLabel("Total time")
                    Text(session.currentTarget.title ?? String(localized: "General practice"))
                        .font(.headline).lineLimit(2).multilineTextAlignment(.center)

                    NavigationLink {
                        WatchItemPicker(session: session) { switchTrigger += 1 }
                    } label: {
                        Label("Next Item", systemImage: "forward.fill").frame(maxWidth: .infinity)
                    }
                    .tint(tint)

                    HStack {
                        Button {
                            model.controller.togglePause()
                        } label: {
                            Image(systemName: session.isPaused ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel(session.isPaused ? "Resume" : "Pause")
                        Button {
                            model.finish()
                        } label: {
                            Image(systemName: "checkmark").frame(maxWidth: .infinity)
                        }
                        .tint(tint)
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Finish")
                    }
                }
            }
            .navigationTitle(session.instrument?.name ?? String(localized: "Practice"))
            .sensoryFeedback(.selection, trigger: switchTrigger)
        }
    }
}

/// Digital Crown scrolls the list of recent and active-repertoire items.
struct WatchItemPicker: View {
    let session: ActiveSession
    let didSwitch: () -> Void
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Button("General practice") { pick(.general) }
            ForEach(model.items(for: session.instrument?.id)) { item in
                Button {
                    pick(.item(item.id, title: item.title))
                } label: {
                    HStack {
                        Text(item.title).lineLimit(2)
                        if session.currentTarget.itemID == item.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("Switch to")
    }

    private func pick(_ target: SegmentTarget) {
        model.controller.switchTo(target)
        didSwitch()
        dismiss()
    }
}

/// Quick 1–5 rating with the Digital Crown, then save.
struct WatchFinishView: View {
    @Environment(WatchModel.self) private var model
    @State private var draft: FinishedSession
    @State private var crown: Double = 0
    @State private var confirmDiscard = false

    init(draft: FinishedSession) { _draft = State(initialValue: draft) }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(DurationText.short(draft.activeDuration)).font(.title2.bold())
                Text("How did it go?").font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { n in
                        Image(systemName: Int(crown.rounded()) >= n ? "star.fill" : "star")
                            .foregroundStyle(.yellow)
                    }
                }
                .focusable()
                .digitalCrownRotation($crown, from: 0, through: 5, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Rating")
                .accessibilityValue(Int(crown.rounded()) == 0 ? "Not set" : "\(Int(crown.rounded())) of 5")

                Button("Save") {
                    let rating = Int(crown.rounded())
                    draft.rating = rating == 0 ? nil : rating
                    model.save(draft)
                }
                .buttonStyle(.borderedProminent)
                Button("Keep Practicing") { model.finishing = nil }
                Button("Discard", role: .destructive) { confirmDiscard = true }
            }
        }
        .confirmationDialog("Discard this session?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { model.discard() }
        }
    }
}

struct WatchSettingsView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Tap every", selection: $model.intervalHapticMinutes) {
            Text("Off").tag(0)
            ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) min").tag($0) }
        }
        .navigationTitle("Interval taps")
    }
}
