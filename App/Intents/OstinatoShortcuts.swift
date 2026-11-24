import AppIntents

/// Siri phrases and Shortcuts app tiles.
struct OstinatoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPracticeIntent(),
            phrases: [
                "Start practice in \(.applicationName)",
                "Start practicing with \(.applicationName)",
                "Practice \(\.$item) in \(.applicationName)"
            ],
            shortTitle: "Start Practice",
            systemImageName: "play.fill")
        AppShortcut(
            intent: SwitchItemIntent(),
            phrases: ["Switch to \(\.$item) in \(.applicationName)"],
            shortTitle: "Switch Item",
            systemImageName: "arrow.left.arrow.right")
        AppShortcut(
            intent: PausePracticeIntent(),
            phrases: ["Pause practice in \(.applicationName)"],
            shortTitle: "Pause",
            systemImageName: "pause.fill")
        AppShortcut(
            intent: ResumePracticeIntent(),
            phrases: ["Resume practice in \(.applicationName)"],
            shortTitle: "Resume",
            systemImageName: "play.fill")
        AppShortcut(
            intent: FinishPracticeIntent(),
            phrases: ["Finish practice in \(.applicationName)", "Stop practicing in \(.applicationName)"],
            shortTitle: "Finish",
            systemImageName: "checkmark")
        AppShortcut(
            intent: LogPracticeIntent(),
            phrases: ["Log practice in \(.applicationName)", "Log \(\.$item) in \(.applicationName)"],
            shortTitle: "Log Practice",
            systemImageName: "plus")
        AppShortcut(
            intent: GetPracticeSummaryIntent(),
            phrases: [
                "How much did I practice in \(.applicationName)",
                "Practice summary for \(\.$range) in \(.applicationName)"
            ],
            shortTitle: "Practice Summary",
            systemImageName: "chart.bar")
    }
}
