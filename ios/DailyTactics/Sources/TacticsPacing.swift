import Foundation

/// Presentation timing only; injectable so tests skip real sleeps.
struct TacticsPacing: Sendable {
    var nextPuzzleDelay: Duration = .milliseconds(300)
    var wrongMoveDisplay: Duration = .milliseconds(550)
    var opponentReplyDelay: Duration = .milliseconds(650)

    static let instant = TacticsPacing(
        nextPuzzleDelay: .milliseconds(1),
        wrongMoveDisplay: .milliseconds(1),
        opponentReplyDelay: .milliseconds(1)
    )
}
