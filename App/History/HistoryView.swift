import PracticeKit
import SwiftData
import SwiftUI

/// Reverse-chronological sessions grouped by day.
struct HistoryView: View {
    @Query(sort: \PracticeSession.startDate, order: .reverse) private var sessions: [PracticeSession]
    @State private var selection: PracticeSession.ID?
    @State private var showingManualLog = false

    private var days: [(day: Date, sessions: [PracticeSession])] {
        let calendar = Calendar.current
        var result: [(Date, [PracticeSession])] = []
        for session in sessions {
            let day = calendar.startOfDay(for: session.startDate)
            if result.last?.0 == day { result[result.count - 1].1.append(session) } else { result.append((day, [session])) }
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(days, id: \.day) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            NavigationLink(value: session.id) { SessionRow(session: session) }
                        }
                    } header: {
                        HStack {
                            Text(day.day, format: .dateTime.weekday(.wide).month().day())
                            Spacer()
                            Text(DurationText.short(day.sessions.reduce(0) { $0 + $1.activeDuration }))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if sessions.isEmpty {
                    EmptyStateView(title: "No sessions yet",
                                   message: "Finished sessions show up here, with time per item.",
                                   systemImage: "calendar",
                                   actionTitle: "Log Past Session") { showingManualLog = true }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Log Past Session", systemImage: "plus") { showingManualLog = true }
                }
            }
        } detail: {
            if let id = selection, let session = sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: session)
            } else {
                ContentUnavailableView("Choose a session", systemImage: "calendar")
            }
        }
        .sheet(isPresented: $showingManualLog) { ManualLogView() }
    }
}

struct SessionRow: View {
    let session: PracticeSession

    var body: some View {
        HStack(spacing: 12) {
            if let instrument = session.instrument {
                InstrumentIcon(instrument, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.sortedSegments.map(\.displayTitle).uniqued().joined(separator: ", "))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.startDate, format: .dateTime.hour().minute())
                    if let rating = session.rating {
                        Label("\(rating)", systemImage: "star.fill").labelStyle(.titleAndIcon)
                    }
                    if !session.tags.isEmpty { Text(session.tags.joined(separator: ", ")) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DurationText.short(session.activeDuration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
