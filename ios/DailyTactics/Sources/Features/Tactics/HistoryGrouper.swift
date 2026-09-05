import Foundation
import PuzzleKit

/// Groups the (potentially very long) round history into calendar weeks,
/// newest first, and names each week for the history list's sections.
/// Pure — injected calendar — so the boundaries are unit-testable.
enum HistoryGrouper {
    struct Week: Identifiable, Equatable {
        /// The week's identity: start-of-week date (stable per calendar week).
        let id: Date
        /// Section title: relative wording for the three most recent weeks,
        /// a date range for anything older.
        let name: String
        /// That week's rounds, newest first.
        let rounds: [RoundSummary]

        /// Total solved/wrong across the week's rounds, for the section header.
        var summary: (puzzles: Int, correct: Int, wrong: Int) {
            var puzzles = 0, correct = 0, wrong = 0
            for round in rounds {
                puzzles += round.puzzleIDs.count
                for outcome in round.outcomes {
                    switch outcome {
                    case .correct: correct += 1
                    case .wrong: wrong += 1
                    case nil: break
                    }
                }
            }
            return (puzzles, correct, wrong)
        }
    }

    static func weeks(
        from rounds: [RoundSummary],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [Week] {
        // Bucket by start-of-week; order inside a bucket keeps the input's
        // (already newest-first from the repository) order.
        var buckets: [Date: [RoundSummary]] = [:]
        for round in rounds {
            buckets[startOfWeek(round.completedAt, calendar: calendar), default: []].append(round)
        }

        let currentWeekStart = startOfWeek(now, calendar: calendar)
        return buckets
            .sorted { $0.key > $1.key }
            .map { start, weekRounds in
                Week(
                    id: start,
                    name: name(for: start, current: currentWeekStart, calendar: calendar),
                    rounds: weekRounds
                )
            }
    }

    /// Start of the calendar week containing `date` (firstWeekday honored).
    private static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Relative wording for the three most recent weeks, else the week's
    /// date range (e.g. "Aug 25–31" / "8月25日–31日").
    private static func name(for start: Date, current: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        // Weeks are 7 days apart; 0/7/14 are the three most recent.
        if day == 0 { return String(localized: "history.week_this") }
        if day == 7 { return String(localized: "history.week_last") }
        if day == 14 { return String(localized: "history.week_prev") }

        let span = (calendar.dateInterval(of: .weekOfYear, for: start)?.end
            .addingTimeInterval(-1)) ?? start
        let fmt = DateFormatter()
        fmt.calendar = calendar
        let sameYear = calendar.isDate(start, equalTo: span, toGranularity: .year)
        if sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: span) {
            fmt.setLocalizedDateFormatFromTemplate("Md")
            return "\(fmt.string(from: start))–\(fmt.string(from: span))"
        }
        fmt.setLocalizedDateFormatFromTemplate("MMdd")
        return "\(fmt.string(from: start)) – \(fmt.string(from: span))"
    }
}
