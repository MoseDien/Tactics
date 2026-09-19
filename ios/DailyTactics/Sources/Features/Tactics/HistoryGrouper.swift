import Foundation
import PuzzleKit

/// Groups round history into calendar weeks (newest first), named for the
/// history sections. Pure; injectable calendar.
enum HistoryGrouper {
    struct Week: Identifiable, Equatable {
        let id: Date
        let name: String
        let rounds: [RoundSummary]

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

    private static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    /// Relative for the three most recent weeks, else a date range.
    private static func name(for start: Date, current: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        if day == 0 { return String(localized: "history.week_this") }
        if day == 7 { return String(localized: "history.week_last") }
        if day == 14 { return String(localized: "history.week_prev") }

        let span = (calendar.dateInterval(of: .weekOfYear, for: start)?.end
            .addingTimeInterval(-1)) ?? start
        let sameYear = calendar.isDate(start, equalTo: span, toGranularity: .year)
        if sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: span) {
            return range(start, span, style: .dateTime.month(.defaultDigits).day(.defaultDigits), calendar: calendar)
        }
        return range(start, span, style: .dateTime.month(.twoDigits).day(.twoDigits), calendar: calendar)
    }

    /// `Date.FormatStyle` carries no calendar in its builder methods, so the
    /// injected calendar (tests pass a fixed one) is applied after building.
    private static func range(_ start: Date, _ span: Date, style: Date.FormatStyle, calendar: Calendar) -> String {
        var style = style
        style.calendar = calendar
        return "\(start.formatted(style)) – \(span.formatted(style))"
    }
}
