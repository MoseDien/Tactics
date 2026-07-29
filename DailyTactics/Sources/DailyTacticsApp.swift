import SwiftUI
import SwiftData

@main
struct DailyTacticsApp: App {
    var body: some Scene {
        WindowGroup {
            TacticsView()
        }
        .modelContainer(for: PuzzleProgress.self)
    }
}
