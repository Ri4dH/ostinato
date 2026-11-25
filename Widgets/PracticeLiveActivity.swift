import ActivityKit
import AppIntents
import PracticeKit
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island. The clock renders itself, so the activity
/// is updated only when the state changes (switch, pause).
struct PracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(Color(hex: context.attributes.instrumentColorHex))
        } dynamicIsland: { context in
            // The Dynamic Island is always dark: use the dark palette step.
            let tint = Color(hex: InstrumentPalette.hex(context.attributes.instrumentColorHex, dark: true))
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.instrumentName, systemImage: context.attributes.instrumentSymbol)
                        .font(.caption).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: context.state).font(.title3.bold()).foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.itemTitle).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityButtons(state: context.state, tint: tint)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : context.attributes.instrumentSymbol)
                    .foregroundStyle(tint)
            } compactTrailing: {
                ActivityTimer(state: context.state).frame(maxWidth: 56).foregroundStyle(tint)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "music.note").foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

struct ActivityTimer: View {
    let state: PracticeActivityAttributes.ContentState

    var body: some View {
        let reference = state.timerReference
        Text(timerInterval: reference...Date.distantFuture,
             pauseTime: state.isPaused ? reference.addingTimeInterval(state.pausedElapsed) : nil,
             countsDown: false, showsHours: true)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

struct ActivityButtons: View {
    let state: PracticeActivityAttributes.ContentState
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: TogglePausePracticeIntent()) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: NextItemIntent()) {
                Label("Next", systemImage: "forward.fill").frame(maxWidth: .infinity)
            }
            Link(destination: URL(string: "ostinato://finish")!) {
                Label("Finish", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.fill.secondary, in: .capsule)
            }
        }
        .font(.caption.bold())
        .buttonStyle(.bordered)
        .tint(tint)
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<PracticeActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(context.attributes.instrumentName, systemImage: context.attributes.instrumentSymbol)
                    .font(.caption)
                    .foregroundStyle(Color(hex: context.attributes.instrumentColorHex))
                Spacer()
                if context.state.isPaused {
                    Label("Paused", systemImage: "pause.fill").font(.caption.bold()).foregroundStyle(.orange)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(context.state.itemTitle).font(.headline).lineLimit(2)
                Spacer()
                ActivityTimer(state: context.state).font(.title.bold())
            }
            ActivityButtons(state: context.state, tint: Color(hex: InstrumentPalette.hex(context.attributes.instrumentColorHex, dark: true)))
        }
        .padding()
    }
}
