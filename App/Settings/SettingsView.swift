import PracticeKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @State private var sync = SyncStatusMonitor()
    @State private var storage: (local: Int64, iCloud: Int64) = (0, 0)
    @State private var reminderDenied = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    NavigationLink { InstrumentsSettingsView() } label: { Label("Instruments", systemImage: "pianokeys") }
                }

                Section {
                    Stepper(value: $settings.goal.dailyMinutes, in: 5...480, step: 5) {
                        LabeledContent("Daily goal", value: String(localized: "\(settings.goal.dailyMinutes) min"))
                    }
                    Stepper(value: $settings.goal.daysPerWeek, in: 1...7) {
                        LabeledContent("Days per week", value: "\(settings.goal.daysPerWeek)")
                    }
                    Toggle("Rest days keep the streak", isOn: $settings.goal.streakFreezeEnabled)
                } header: {
                    Text("Goal")
                } footer: {
                    Text(settings.goal.streakFreezeEnabled && settings.goal.daysPerWeek < 7
                         ? "Up to \(7 - settings.goal.daysPerWeek) rest days a week won't break your streak."
                         : "Every day counts toward your streak.")
                }

                Section {
                    Toggle("Daily reminder", isOn: $settings.reminderEnabled)
                    if settings.reminderEnabled {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text(reminderDenied ? "Notifications are off for Ostinato. Turn them on in Settings to get reminders."
                         : "At most one a day, and skipped once you reach your goal.")
                }

                Section("During practice") {
                    Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
                    Stepper(value: $settings.a4Reference, in: NoteMath.a4Range, step: 1) {
                        LabeledContent("Tuning reference", value: "A4 = \(Int(settings.a4Reference)) Hz")
                    }
                }

                iCloudSection

                Section {
                    LabeledContent("On this device", value: storage.local.formatted(.byteCount(style: .file)))
                    if model.recordingFiles.iCloudAvailable {
                        LabeledContent("In iCloud", value: storage.iCloud.formatted(.byteCount(style: .file)))
                    }
                    Picker("Delete recordings older than", selection: $settings.recordingRetentionDays) {
                        Text("Never").tag(0)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                } header: {
                    Text("Recordings")
                }

                Section("Your data") {
                    NavigationLink { DataManagementView() } label: {
                        Label("Export, Import and Delete", systemImage: "externaldrive")
                    }
                    .accessibilityIdentifier("dataManagement")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    Text("No accounts. No tracking. Your data stays on your devices and your iCloud.")
                        .foregroundStyle(.secondary)
                    Link("Privacy Policy", destination: URL(string: "https://ri4dh.github.io/ostinato/privacy/")!)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .task {
                await model.refreshICloudStatus()
                sync.start(syncEnabled: settings.syncEnabled, signedIn: settings.iCloudSignedIn)
                storage = model.recordingFiles.bytesUsed()
            }
            .onChange(of: settings.goal) { model.refreshDerivedState() }
            .onChange(of: settings.reminderEnabled) { _, enabled in
                Task {
                    if enabled, await !model.reminders.requestAuthorization() {
                        reminderDenied = true
                        settings.reminderEnabled = false
                    }
                    await model.reminders.reschedule(settings: settings, todayMinutes: model.todayMinutes())
                }
            }
            .onChange(of: settings.reminderMinutes) {
                Task { await model.reminders.reschedule(settings: settings, todayMinutes: model.todayMinutes()) }
            }
            .onChange(of: settings.recordingRetentionDays) { _, days in
                model.recordingFiles.prune(olderThan: days, in: context)
                storage = model.recordingFiles.bytesUsed()
            }
        }
    }

    private var iCloudSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Sync with iCloud", isOn: $settings.syncEnabled)
                .disabled(!sync.isSignedIn)
            Toggle("Sync recordings to iCloud", isOn: $settings.syncRecordings)
                .disabled(!sync.isSignedIn || !settings.syncEnabled)
            Label(sync.text, systemImage: sync.symbol)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sync status: \(sync.text)")
            if model.pendingSyncChange {
                Text("This change applies after you finish the current session.")
                    .font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("iCloud")
        } footer: {
            Text(sync.isSignedIn
                 ? "Uses your own iCloud. We never see your data. Turning sync off keeps everything on this device."
                 : "Sign in to iCloud in the Settings app to sync between your devices. Ostinato works fully offline.")
        }
        .onChange(of: settings.syncEnabled) { _, enabled in
            model.applySyncSetting()
            sync.start(syncEnabled: enabled, signedIn: settings.iCloudSignedIn)
            Task { await model.recordingFiles.applySync(enabled: enabled && settings.syncRecordings, in: model.context) }
        }
        .onChange(of: settings.syncRecordings) { _, enabled in
            Task {
                await model.recordingFiles.resolveICloud(containerID: model.identifiers.cloudKitContainer)
                await model.recordingFiles.applySync(enabled: settings.syncEnabled && enabled, in: model.context)
                storage = model.recordingFiles.bytesUsed()
            }
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: settings.reminderDateComponents) ?? Date() },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                settings.reminderMinutes = (c.hour ?? 18) * 60 + (c.minute ?? 0)
            })
    }
}
