import PracticeKit
import SwiftData
import SwiftUI

/// Skippable, ≤ 3 screens: instruments, goal, reminder. Never asks for the mic.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var selectedPresets: Set<String> = []
    @State private var dailyMinutes = 30
    @State private var daysPerWeek = 5
    @State private var wantsReminder = false
    @State private var reminderTime = Calendar.current.date(from: DateComponents(hour: 18)) ?? Date()

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case 0: instrumentsPage
                case 1: goalPage
                default: reminderPage
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish(skipped: true) }.accessibilityIdentifier("skipOnboarding")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    if page < 2 { withAnimation { page += 1 } } else { finish(skipped: false) }
                } label: {
                    Text(page < 2 ? "Next" : "Start Practicing").font(.headline).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.glassProminent)
                .padding()
                .accessibilityIdentifier("onboardingNext")
            }
        }
        .interactiveDismissDisabled()
    }

    private var instrumentsPage: some View {
        InstrumentPresetPicker(selected: $selectedPresets, hint: "Pick one or more. You can add your own later.")
            .navigationTitle("What do you play?")
            .navigationBarTitleDisplayMode(.large)
    }

    private var goalPage: some View {
        Form {
            Section {
                Stepper(value: $dailyMinutes, in: 5...480, step: 5) {
                    LabeledContent("Minutes a day", value: "\(dailyMinutes)")
                }
                Stepper(value: $daysPerWeek, in: 1...7) {
                    LabeledContent("Days a week", value: "\(daysPerWeek)")
                }
            } footer: {
                Text("Rest days are built in. Missing a day within your weekly goal won't break your streak.")
            }
        }
        .navigationTitle("Set a goal")
    }

    private var reminderPage: some View {
        Form {
            Section {
                Toggle("Remind me to practice", isOn: $wantsReminder)
                if wantsReminder {
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("One gentle reminder a day, skipped once you've reached your goal.")
            }
            Section {
                Label("No account needed. Your data stays on your devices and your own iCloud.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Reminder")
    }

    private func finish(skipped: Bool) {
        let existing = (try? context.fetchCount(FetchDescriptor<Instrument>())) ?? 0
        let presets = InstrumentPreset.all.filter { selectedPresets.contains($0.key) }
        for (index, preset) in presets.enumerated() {
            context.insert(Instrument(preset: preset, sortIndex: existing + index))
        }
        try? context.save()
        if !skipped {
            settings.goal = GoalSettings(dailyMinutes: dailyMinutes, daysPerWeek: daysPerWeek,
                                         streakFreezeEnabled: settings.goal.streakFreezeEnabled)
            if wantsReminder {
                let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
                settings.reminderMinutes = (c.hour ?? 18) * 60 + (c.minute ?? 0)
                Task {
                    let granted = await AppModel.shared.reminders.requestAuthorization()
                    settings.reminderEnabled = granted
                    await AppModel.shared.reminders.reschedule(settings: settings, todayMinutes: 0)
                }
            }
        }
        if let first = try? context.fetch(FetchDescriptor<Instrument>(sortBy: [SortDescriptor(\.sortIndex)])).first {
            settings.lastInstrumentID = settings.lastInstrumentID ?? first.id
        }
        settings.hasOnboarded = true
        AppModel.shared.refreshDerivedState()
    }
}
