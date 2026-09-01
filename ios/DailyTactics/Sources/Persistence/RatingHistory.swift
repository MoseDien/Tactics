import Foundation
import SwiftData

/// One rating sample per completed batch: the settled rating right after the
/// batch's final puzzle resolved (including that puzzle's delta). Together the
/// rows form the rating-over-time series shown as a chart in Settings. The
/// current rating itself stays a `UserDefaults` scalar; snapshots only append.
@Model
final class RatingSnapshot {
    var id: UUID
    var recordedAt: Date
    var rating: Int

    init(rating: Int) {
        self.id = UUID()
        self.recordedAt = .now
        self.rating = rating
    }
}

@MainActor
extension PuzzleProgressStore {
    func recordRatingSnapshot(value: Int) {
        context.insert(RatingSnapshot(rating: value))
        try? context.save()
    }

    /// All snapshots oldest-first, ready for a time-series chart.
    func ratingHistory() -> [RatingSnapshot] {
        let descriptor = FetchDescriptor<RatingSnapshot>(sortBy: [SortDescriptor(\RatingSnapshot.recordedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }
}
