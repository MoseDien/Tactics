import Foundation
import SwiftData

/// One completed round: the puzzle ids in order plus per-puzzle outcomes.
@Model
public final class RoundHistory {
    public var id: UUID
    public var completedAt: Date
    public var puzzleIDs: [String]
    public var outcomes: [String]

    public init(puzzleIDs: [String], outcomes: [String]) {
        self.id = UUID()
        self.completedAt = .now
        self.puzzleIDs = puzzleIDs
        self.outcomes = outcomes
    }
}
