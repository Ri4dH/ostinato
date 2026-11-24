import PracticeKit
import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case practice, repertoire, history, stats, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var selectedTab: AppTab = .practice

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selectedTab) {
            Tab("Practice", systemImage: "music.note", value: AppTab.practice) {
                PracticeHomeView()
            }
            Tab("Repertoire", systemImage: "music.note.list", value: AppTab.repertoire) {
                RepertoireView()
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView()
            }
            Tab("Stats", systemImage: "chart.bar", value: AppTab.stats) {
                StatsView()
            }
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(Color(hex: model.sessionController.active?.instrument?.colorHex ?? InstrumentPalette.defaultHex))
        .fullScreenCover(isPresented: $model.isShowingActiveSession) {
            ActiveSessionView()
                .environment(model)
                .environment(settings)
                .modelContainer(model.container)
        }
        .fullScreenCover(isPresented: .constant(!settings.hasOnboarded)) {
            OnboardingView()
                .environment(settings)
                .modelContainer(model.container)
        }
        .sheet(item: $model.restoredSessionPrompt) { session in
            ResumeSessionPrompt(session: session)
                .presentationDetents([.medium])
        }
        .bannerOverlay($model.banner)
        .sessionConflictAlert()
        .onOpenURL { url in
            // ostinato://finish (Live Activity), ostinato://session (widgets)
            guard url.scheme == "ostinato", model.sessionController.isActive else { return }
            model.restoredSessionPrompt = nil
            model.isShowingActiveSession = true
            if url.host() == "finish" { model.beginFinish() }
        }
    }
}

/// "You have a session in progress" after the app was closed mid-session.
struct ResumeSessionPrompt: View {
    let session: ActiveSession
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "timer")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Session in progress")
                .font(.title2.bold())
            Text("Started \(session.startDate, format: .dateTime.hour().minute()). \(DurationText.spoken(session.elapsed(at: Date()))) so far.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button {
                    dismiss()
                    model.isShowingActiveSession = true
                } label: {
                    Text("Resume").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    dismiss()
                    model.isShowingActiveSession = true
                    model.beginFinish()
                } label: {
                    Text("Finish").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)

                Button("Discard", role: .destructive) { confirmingDiscard = true }
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .confirmationDialog("Discard this session?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Session", role: .destructive) {
                model.discardActiveSession()
                dismiss()
            }
            Button("Keep Session", role: .cancel) {}
        } message: {
            Text("The time from this session won't be saved.")
        }
    }
}

private struct SessionConflictAlert: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.alert("Two sessions are running", isPresented: Binding(
            get: { model.conflict != nil },
            set: { if !$0, model.conflict != nil { model.resolveConflict(merge: false) } }),
            presenting: model.conflict) { _ in
            Button("Combine into One") { model.resolveConflict(merge: true) }
            Button("Keep Earlier Only", role: .destructive) { model.resolveConflict(merge: false) }
        } message: { conflict in
            Text(conflict.loser.source == .watch
                 ? "Your watch started a separate session. Combine them, or keep the one that started first?"
                 : "Your iPhone started a separate session. Combine them, or keep the one that started first?")
        }
    }
}

extension View {
    func sessionConflictAlert() -> some View { modifier(SessionConflictAlert()) }

    /// A transient message at the top of the screen.
    func bannerOverlay(_ banner: Binding<Banner?>) -> some View {
        overlay(alignment: .top) {
            if let value = banner.wrappedValue {
                Label(value.message, systemImage: value.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: value.id) {
                        try? await Task.sleep(for: .seconds(4))
                        banner.wrappedValue = nil
                    }
                    .onTapGesture { banner.wrappedValue = nil }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.snappy, value: banner.wrappedValue)
    }
}
