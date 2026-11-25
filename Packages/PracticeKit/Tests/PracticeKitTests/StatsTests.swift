import Foundation
import Testing
@testable import PracticeKit

@Suite("Stats, streaks and goals")
struct StatsTests {
    let ny = calendar("America/New_York")
    var stats: StatsCalculator { StatsCalculator(calendar: ny) }

    func session(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 18, minutes: Double, tz: String = "America/New_York",
                 segments: [SegmentRecord] = [], rating: Int? = nil) -> SessionRecord {
        SessionRecord(startDate: date(y, m, d, h, tz: tz), activeDuration: minutes * 60,
                      rating: rating, segments: segments)
    }

    @Test func dailyStreakWithoutRestDays() {
        let goal = GoalSettings(daysPerWeek: 7, streakFreezeEnabled: false)
        let records = [1, 2, 3, 5, 6].map { session(2026, 3, $0, minutes: 20) }
        let info = stats.streak(records, goal: goal, now: date(2026, 3, 6, 21))
        #expect(info.current == 2)
        #expect(info.longest == 3)
        #expect(!info.isPendingToday)
    }

    @Test func todayDoesNotBreakStreak() {
        let goal = GoalSettings(daysPerWeek: 7, streakFreezeEnabled: false)
        let records = [3, 4, 5].map { session(2026, 3, $0, minutes: 20) }
        let info = stats.streak(records, goal: goal, now: date(2026, 3, 6, 9))
        #expect(info.current == 3)
        #expect(info.isPendingToday)
    }

    @Test func restDaysWithinWeeklyAllowanceKeepStreak() {
        // 5 days/week goal → 2 rest days allowed per calendar week (Mon–Sun).
        let goal = GoalSettings(daysPerWeek: 5, streakFreezeEnabled: true)
        // Week of Mon Mar 2: practice Mon, Tue, Thu, Fri, Sun (skip Wed, Sat).
        let days = [2, 3, 5, 6, 8, 9]
        let records = days.map { session(2026, 3, $0, minutes: 30) }
        let info = stats.streak(records, goal: goal, now: date(2026, 3, 9, 20))
        #expect(info.current == 6)
    }

    @Test func tooManyMissedDaysBreakStreak() {
        let goal = GoalSettings(daysPerWeek: 5, streakFreezeEnabled: true)
        // Mon, then skip Tue Wed Thu (3 > 2 allowed), then Fri Sat.
        let records = [2, 6, 7].map { session(2026, 3, $0, minutes: 30) }
        let info = stats.streak(records, goal: goal, now: date(2026, 3, 7, 20))
        #expect(info.current == 2)
        #expect(info.longest == 2)
    }

    @Test func lateNightSessionCountsTowardStartDay() {
        let late = SessionRecord(startDate: date(2026, 3, 2, 23, 50), activeDuration: 3600)
        let totals = stats.dayTotals([late])
        #expect(totals[ny.startOfDay(for: date(2026, 3, 2))] == 3600)
        #expect(totals[ny.startOfDay(for: date(2026, 3, 3))] == nil)
    }

    @Test func streakAcrossDSTTransition() {
        let goal = GoalSettings(daysPerWeek: 7, streakFreezeEnabled: false)
        // US DST begins Sun Mar 8 2026 (a 23-hour day).
        let records = [6, 7, 8, 9, 10].map { session(2026, 3, $0, 1, minutes: 15) }
        let info = stats.streak(records, goal: goal, now: date(2026, 3, 10, 22))
        #expect(info.current == 5)
        let fallBack = [31, 1, 2].enumerated().map { i, d in session(2026, i == 0 ? 10 : 11, d, 1, minutes: 15) }
        #expect(stats.streak(fallBack, goal: goal, now: date(2026, 11, 2, 22)).current == 3)
    }

    @Test func dayBoundariesFollowTheCalendarTimezone() {
        // 23:30 in New York is already the next day in Berlin.
        let record = SessionRecord(startDate: date(2026, 5, 4, 23, 30), activeDuration: 600)
        let berlin = StatsCalculator(calendar: calendar("Europe/Berlin"))
        #expect(stats.dayTotals([record]).keys.first == ny.startOfDay(for: date(2026, 5, 4)))
        let berlinCal = calendar("Europe/Berlin")
        #expect(berlin.dayTotals([record]).keys.first == berlinCal.startOfDay(for: date(2026, 5, 5, 12, tz: "Europe/Berlin")))
    }

    @Test func bucketTotalsIncludeZeroDays() {
        let records = [session(2026, 3, 3, minutes: 30), session(2026, 3, 3, 20, minutes: 15), session(2026, 3, 5, minutes: 10)]
        let week = StatsRange.week.interval(containing: date(2026, 3, 4), calendar: ny, earliest: nil)
        let totals = stats.bucketTotals(records, in: week)
        #expect(totals.count == 7)
        #expect(totals.map(\.minutes) == [0, 45, 0, 10, 0, 0, 0])
    }

    @Test func itemAndCategoryTotals() {
        let a = UUID(), b = UUID()
        let records = [
            session(2026, 3, 3, minutes: 40, segments: [
                SegmentRecord(itemID: nil, category: nil, duration: 600),
                SegmentRecord(itemID: a, category: .piece, duration: 1200),
                SegmentRecord(itemID: b, category: .scale, duration: 600)
            ]),
            session(2026, 3, 4, minutes: 20, segments: [SegmentRecord(itemID: a, category: .piece, duration: 1200)])
        ]
        #expect(stats.topItems(records).map(\.key) == [a, b])
        #expect(stats.topItems(records).first?.seconds == 2400)
        let categories = Dictionary(uniqueKeysWithValues: stats.totalsByCategory(records).map { ($0.key, $0.seconds) })
        #expect(categories == [.piece: 2400, .scale: 600, .other: 600])
        #expect(stats.itemTotal(a, records) == 2400)
        let weekly = stats.itemWeeklyTotals(a, records, weeks: 4, now: date(2026, 3, 5))
        #expect(weekly.count == 4)
        #expect(weekly.last?.seconds == 2400)
    }

    @Test func goalCompletion() {
        let goal = GoalSettings(dailyMinutes: 30, daysPerWeek: 3)
        let records = [2, 3, 4].map { session(2026, 3, $0, minutes: 30) } + [session(2026, 3, 5, minutes: 10)]
        let month = StatsRange.month.interval(containing: date(2026, 3, 10), calendar: ny, earliest: nil)
        let result = stats.goalCompletion(records, goal: goal, in: month, now: date(2026, 3, 10))
        #expect(result.daysElapsed == 10)
        #expect(result.daysMet == 3)
        #expect(result.weeksMet == 1)
        #expect(result.weeksElapsed == 3)  // Feb 23 week (Mar 1), Mar 2 week, Mar 9 week
    }

    @Test func weeklyRatingAverages() {
        let records = [session(2026, 3, 2, minutes: 10, rating: 4), session(2026, 3, 3, minutes: 10, rating: 2),
                       session(2026, 3, 10, minutes: 10, rating: 5)]
        let all = StatsRange.all.interval(containing: date(2026, 3, 12), calendar: ny, earliest: date(2026, 3, 1))
        let avgs = stats.weeklyAverages(records, in: all)
        #expect(avgs.map(\.rating) == [3, 5])
    }

    @Test func largeDatasetAggregatesQuickly() {
        // 10,000 sessions / 50,000 segments (spec performance target).
        let items = (0..<200).map { _ in UUID() }
        let start = date(2020, 1, 1)
        let records = (0..<10_000).map { i in
            SessionRecord(
                startDate: start.addingTimeInterval(Double(i) * 5 * 3600),
                activeDuration: 3000,
                instrumentID: nil,
                rating: i % 5 + 1,
                segments: (0..<5).map { j in
                    SegmentRecord(itemID: items[(i + j) % items.count], category: .piece, duration: 600)
                }
            )
        }
        let now = records.last!.startDate
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let all = StatsRange.all.interval(containing: now, calendar: ny, earliest: start)
            _ = stats.bucketTotals(records, in: all, bucket: .month)
            _ = stats.topItems(records)
            _ = stats.totalsByCategory(records)
            _ = stats.streak(records, goal: .default, now: now)
            _ = stats.goalCompletion(records, goal: .default, in: all, now: now)
            _ = stats.weeklyAverages(records, in: all)
        }
        // Debug build, possibly in a busy simulator: a regression guard, not
        // the device target (that is release on an iPhone 13-class device).
        #expect(elapsed < .seconds(1))
    }

    @Test func durationFormatting() {
        #expect(DurationText.clock(754) == "12:34")
        #expect(DurationText.clock(3723) == "1:02:03")
        #expect(DurationText.minutes(119) == 1)
    }
}

@Suite("Duration text")
struct DurationTextTests {
    @Test func zeroReadsAsMinutes() {
        #expect(DurationText.short(0) == "0 min")
        #expect(DurationText.short(45) == "45 sec")
        #expect(DurationText.short(3_900) == "1 hr, 5 min")
    }
}
