import Foundation

/// Interaction pacing for the training loop. Injectable so tests run without
/// real sleeps; the durations are presentation timing only — the session state
/// machine (`PuzzleSession`) stays pure and timing-free.
struct TacticsPacing: Sendable {
    /// Beat before the next puzzle appears.
    var nextPuzzleDelay: Duration = .milliseconds(300)
    /// How long a wrong move stays demonstrated on the board.
    var wrongMoveDisplay: Duration = .milliseconds(550)
    /// Pause before the machine's reply is applied.
    var opponentReplyDelay: Duration = .milliseconds(450)

    /// Test pace: every delay collapses to near-zero.
    static let instant = TacticsPacing(
        nextPuzzleDelay: .milliseconds(1),
        wrongMoveDisplay: .milliseconds(1),
        opponentReplyDelay: .milliseconds(1)
    )
}
