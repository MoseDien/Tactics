import XCTest
import PuzzleKit
@testable import DailyTactics

final class HistoryGrouperTests: XCTestCase {
    /// Fixed calendar (Gregorian, Monday-first) so week boundaries are
    /// deterministic regardless of the machine running the tests.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func round(at date: Date, puzzles: Int = 5, outcomes: [PuzzleOutcome?] = [.correct, .correct, .wrong, .correct, nil]) -> RoundSummary {
        RoundSummary(
            id: UUID(),
            completedAt: date,
            puzzleIDs: (0..<puzzles).map { "p\($0)-\(date.timeIntervalSince1970)" },
            outcomes: Array(outcomes.prefix(puzzles))
        )
    }

    func testRoundsOnEitherSideOfWeekBoundaryLandInSeparateWeeks() {
        // Sunday 23:59 and the following Monday 00:01 (Monday-first calendar).
        let sundayNight = date(2026, 8, 30, hour: 23, minute: 59)
        let mondayEarly = date(2026, 8, 31, hour: 0, minute: 1)
        let now = mondayEarly

        let weeks = HistoryGrouper.weeks(from: [round(at: sundayNight), round(at: mondayEarly)], calendar: calendar, now: now)

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].rounds.count, 1, "newer week first")
        XCTAssertEqual(weeks[1].rounds.count, 1)
    }

    func testWeeksSortNewestFirstAndKeepRoundOrder() {
        let now = date(2026, 9, 4)
        let old = round(at: date(2026, 8, 10))
        let mid = round(at: date(2026, 8, 26))
        let newest = round(at: date(2026, 9, 3))

        let weeks = HistoryGrouper.weeks(from: [old, mid, newest], calendar: calendar, now: now)

        XCTAssertEqual(weeks.map(\.rounds.count), [1, 1, 1])
        XCTAssertTrue(weeks[0].id > weeks[1].id)
        XCTAssertTrue(weeks[1].id > weeks[2].id)
        XCTAssertEqual(weeks[0].rounds.first?.id, newest.id)
    }

    func testSameWeekRoundsShareOneSection() {
        let now = date(2026, 9, 4)
        let tuesday = round(at: date(2026, 9, 1))
        let thursday = round(at: date(2026, 9, 3))

        let weeks = HistoryGrouper.weeks(from: [tuesday, thursday], calendar: calendar, now: now)

        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].rounds.count, 2)
    }

    func testSummaryCountsAcrossTheWeeksRounds() {
        let now = date(2026, 9, 4)
        let r1 = round(at: date(2026, 9, 1), puzzles: 2, outcomes: [.correct, .wrong])
        let r2 = round(at: date(2026, 9, 2), puzzles: 3, outcomes: [.correct, .correct, .correct])

        let week = HistoryGrouper.weeks(from: [r1, r2], calendar: calendar, now: now)[0]
        let summary = week.summary

        XCTAssertEqual(summary.puzzles, 5)
        XCTAssertEqual(summary.correct, 4)
        XCTAssertEqual(summary.wrong, 1)
    }

    func testRecentWeeksUseRelativeNames() {
        // Anchor to a Wednesday; this week / -7d / -14d are the relative ones.
        let now = date(2026, 9, 2)
        let thisWeek = round(at: date(2026, 9, 1))
        let lastWeek = round(at: now.addingTimeInterval(-7 * 86_400))
        let prevWeek = round(at: now.addingTimeInterval(-14 * 86_400))

        let weeks = HistoryGrouper.weeks(from: [thisWeek, lastWeek, prevWeek], calendar: calendar, now: now)

        XCTAssertEqual(weeks[0].name, String(localized: "history.week_this"))
        XCTAssertEqual(weeks[1].name, String(localized: "history.week_last"))
        XCTAssertEqual(weeks[2].name, String(localized: "history.week_prev"))
    }

    func testOlderWeeksUseDateRangeName() {
        let now = date(2026, 9, 2)
        let older = round(at: now.addingTimeInterval(-30 * 86_400))

        let name = HistoryGrouper.weeks(from: [older], calendar: calendar, now: now)[0].name

        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, String(localized: "history.week_this"))
        // A range name contains the separator we format with.
        XCTAssertTrue(name.contains("–") || name.contains("-"), "expected a date range, got \(name)")
    }
}
