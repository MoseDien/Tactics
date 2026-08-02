import Foundation
import SwiftData

@Model
final class RatingAssessment {
    @Attribute(.unique) var id: String
    var isCompleted: Bool
    var baselineRating: Int?
    var completedAt: Date?
    var completedPuzzleIDs: [String]

    init(id: String = "initial-rating") {
        self.id = id
        self.isCompleted = false
        self.baselineRating = nil
        self.completedAt = nil
        self.completedPuzzleIDs = []
    }
}

struct RatingAssessmentPlan: Sendable {
    let puzzles: [Puzzle]

    static func make(from puzzles: [Puzzle], count: Int = 10) -> RatingAssessmentPlan {
        guard !puzzles.isEmpty else { return RatingAssessmentPlan(puzzles: []) }
        let sorted = puzzles.sorted { ($0.rating ?? 1500) < ($1.rating ?? 1500) }
        let bucketCount = min(count, sorted.count)
        let buckets = stride(from: 0, to: sorted.count, by: max(1, sorted.count / bucketCount)).map {
            Array(sorted[$0..<min($0 + max(1, sorted.count / bucketCount), sorted.count)])
        }
        var selected = buckets.compactMap { $0.randomElement() }
        if selected.count < count {
            let remaining = sorted.filter { puzzle in !selected.contains { $0.id == puzzle.id } }
            selected.append(contentsOf: remaining.shuffled().prefix(count - selected.count))
        }
        return RatingAssessmentPlan(puzzles: Array(selected.prefix(count)).shuffled())
    }
}

enum RatingAssessmentLoader {
    static func loadBundled() -> [Puzzle] {
        guard let url = Bundle.main.url(forResource: "rating_puzzles", withExtension: "json") else {
            return []
        }
        do {
            return try JSONDecoder().decode([Puzzle].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Malformed rating_puzzles.json: \(error)")
            return []
        }
    }
}

@MainActor
struct RatingAssessmentStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func recordProgress(puzzleID: String) {
        let assessment = fetchOrCreate()
        guard !assessment.completedPuzzleIDs.contains(puzzleID) else { return }
        assessment.completedPuzzleIDs.append(puzzleID)
        try? context.save()
    }

    func complete(baselineRating: Int) {
        let assessment = fetchOrCreate()
        guard !assessment.isCompleted else { return }
        assessment.baselineRating = baselineRating
        assessment.isCompleted = true
        assessment.completedAt = .now
        try? context.save()
    }

    func reset() {
        let assessment = fetchOrCreate()
        assessment.isCompleted = false
        assessment.baselineRating = nil
        assessment.completedAt = nil
        assessment.completedPuzzleIDs = []
        try? context.save()
    }

    func current() -> RatingAssessment { fetchOrCreate() }

    private func fetchOrCreate() -> RatingAssessment {
        let descriptor = FetchDescriptor<RatingAssessment>(
            predicate: #Predicate { $0.id == "initial-rating" }
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let assessment = RatingAssessment()
        context.insert(assessment)
        try? context.save()
        return assessment
    }
}
