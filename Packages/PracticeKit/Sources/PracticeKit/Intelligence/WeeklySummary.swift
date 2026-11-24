import Foundation

/// Compact, pre-aggregated facts about a week. This, never raw logs, is what
/// the on-device model sees. Must stay well inside the model's context.
public struct WeeklySummaryInput: Codable, Sendable, Equatable {
    public struct ItemLine: Codable, Sendable, Equatable {
        public var title: String
        public var minutes: Int
        public var category: String
    }

    public var weekStart: Date
    public var totalMinutes: Int
    public var previousWeekMinutes: Int
    public var daysPracticed: Int
    public var goalDaysPerWeek: Int
    public var goalDailyMinutes: Int
    public var streak: Int
    public var topItems: [ItemLine]
    public var categoryShares: [String: Int]   // percent
    public var averageRating: Double?
    public var averageFocus: Double?
    public var notes: [String]

    public static let maxItems = 8
    public static let maxNotes = 3
    public static let maxTitleLength = 40
    public static let maxNoteLength = 120

    /// Builds the input from records of the current and previous week.
    public static func make(
        records: [SessionRecord], itemTitles: [UUID: (title: String, category: ItemCategory)],
        notes: [String], goal: GoalSettings, now: Date, calendar: Calendar
    ) -> WeeklySummaryInput {
        let stats = StatsCalculator(calendar: calendar)
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 0)
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) ?? week.start
        let previous = DateInterval(start: previousStart, end: week.start)
        let thisWeek = records.filter { week.contains($0.startDate) }
        let total = stats.total(thisWeek)

        let top = stats.topItems(thisWeek, limit: maxItems).compactMap { entry -> ItemLine? in
            guard let info = itemTitles[entry.key] else { return nil }
            return ItemLine(title: String(info.title.prefix(maxTitleLength)), minutes: DurationText.minutes(entry.seconds),
                            category: info.category.rawValue)
        }
        var shares: [String: Int] = [:]
        if total > 0 {
            for c in stats.totalsByCategory(thisWeek) {
                shares[c.key.rawValue] = Int((c.seconds / total * 100).rounded())
            }
        }
        func average(_ values: [Int]) -> Double? {
            values.isEmpty ? nil : (Double(values.reduce(0, +)) / Double(values.count) * 10).rounded() / 10
        }
        return WeeklySummaryInput(
            weekStart: week.start,
            totalMinutes: DurationText.minutes(total),
            previousWeekMinutes: DurationText.minutes(stats.total(records, in: previous)),
            daysPracticed: Set(thisWeek.map { calendar.startOfDay(for: $0.startDate) }).count,
            goalDaysPerWeek: goal.daysPerWeek,
            goalDailyMinutes: goal.dailyMinutes,
            streak: stats.streak(records, goal: goal, now: now).current,
            topItems: top,
            categoryShares: shares,
            averageRating: average(thisWeek.compactMap(\.rating)),
            averageFocus: average(thisWeek.compactMap(\.focus)),
            notes: notes.lazy.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                .prefix(maxNotes).map { String($0.prefix(maxNoteLength)) }
        )
    }

    /// Plain-text facts for the model prompt.
    public var promptText: String {
        var lines = [
            "Total this week: \(totalMinutes) min (last week: \(previousWeekMinutes) min)",
            "Days practiced: \(daysPracticed) of goal \(goalDaysPerWeek); daily goal \(goalDailyMinutes) min",
            "Current streak: \(streak) days"
        ]
        if !topItems.isEmpty {
            lines.append("Time per item: " + topItems.map { "\($0.title) (\($0.category)) \($0.minutes) min" }.joined(separator: "; "))
        }
        if !categoryShares.isEmpty {
            lines.append("Category share: " + categoryShares.sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)%" }.joined(separator: ", "))
        }
        if let averageRating { lines.append("Average session rating: \(averageRating)/5") }
        if let averageFocus { lines.append("Average focus: \(averageFocus)/5") }
        if !notes.isEmpty { lines.append("Practice notes: " + notes.joined(separator: " | ")) }
        return lines.joined(separator: "\n")
    }

    /// Rough token estimate (~4 characters per token).
    public var estimatedTokens: Int { (promptText.count + 3) / 4 }
}

/// Output shape for a weekly summary (rules-based or generated).
public struct WeeklySummary: Sendable, Equatable {
    public var headline: String
    public var observations: [String]
    public var suggestion: String
    public var isGenerated: Bool

    public init(headline: String, observations: [String], suggestion: String, isGenerated: Bool) {
        self.headline = headline
        self.observations = Array(observations.prefix(3))
        self.suggestion = suggestion
        self.isGenerated = isGenerated
    }
}

/// The always-available fallback. Deterministic and plain.
public enum RulesBasedSummary {
    public static func make(_ input: WeeklySummaryInput) -> WeeklySummary {
        let total = DurationText.spoken(TimeInterval(input.totalMinutes * 60))
        guard input.totalMinutes > 0 else {
            return WeeklySummary(
                headline: String(localized: "No practice logged this week", bundle: .module),
                observations: [],
                suggestion: String(localized: "A short session still counts. Try 10 minutes today.", bundle: .module),
                isGenerated: false)
        }

        let headline: String
        if let top = input.topItems.first, input.totalMinutes > 0, top.minutes * 2 >= input.totalMinutes {
            headline = String(localized: "A focused week on \(top.title)", bundle: .module)
        } else if input.daysPracticed >= input.goalDaysPerWeek {
            headline = String(localized: "Goal met: \(input.daysPracticed) practice days", bundle: .module)
        } else {
            headline = String(localized: "\(total) of practice this week", bundle: .module)
        }

        var observations: [String] = []
        if input.previousWeekMinutes > 0 {
            let change = Double(input.totalMinutes - input.previousWeekMinutes) / Double(input.previousWeekMinutes)
            if change >= 0.15 {
                observations.append(String(localized: "Up \(Int((change * 100).rounded()))% on last week.", bundle: .module))
            } else if change <= -0.15 {
                observations.append(String(localized: "Down \(Int((-change * 100).rounded()))% on last week.", bundle: .module))
            } else {
                observations.append(String(localized: "About the same as last week.", bundle: .module))
            }
        }
        if let top = input.topItems.first {
            observations.append(String(localized: "Most time went to \(top.title) (\(top.minutes) min).", bundle: .module))
        }
        if let focus = input.averageFocus {
            observations.append(String(localized: "Average focus was \(focus.formatted(.number.precision(.fractionLength(1)))) out of 5.", bundle: .module))
        }

        let scaleShare = (input.categoryShares[ItemCategory.scale.rawValue] ?? 0)
            + (input.categoryShares[ItemCategory.technique.rawValue] ?? 0)
        let suggestion: String
        if input.daysPracticed < input.goalDaysPerWeek {
            suggestion = String(localized: "Add \(input.goalDaysPerWeek - input.daysPracticed) more short sessions to reach your weekly goal.", bundle: .module)
        } else if scaleShare < 10 {
            suggestion = String(localized: "Scales and technique were \(scaleShare)% of your time. A 10-minute warm-up could help.", bundle: .module)
        } else {
            suggestion = String(localized: "Keep the same rhythm next week.", bundle: .module)
        }
        return WeeklySummary(headline: headline, observations: observations, suggestion: suggestion, isGenerated: false)
    }
}
