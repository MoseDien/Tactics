import Foundation
import SwiftData

/// One rating sample per completed round: the settled rating right after the
/// round's final puzzle resolved (including that puzzle's delta). Together the
/// rows form the rating-over-time series shown as a chart in Settings. The
/// current rating itself stays a `UserDefaults` scalar; snapshots only append.
@Model
public final class RatingSnapshot {
    public var id: UUID
    public var recordedAt: Date
    public var rating: Int

    public init(rating: Int) {
        self.id = UUID()
        self.recordedAt = .now
        self.rating = rating
    }
}
