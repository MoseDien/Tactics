import SwiftUI
import SwiftData

/// First-launch screen that bulk-imports the entire bundled puzzle library
/// (all 10 rating tiers) into SwiftData. On completion it flips the
/// `LibraryStateStore.importedKey` flag (observed by `RootView` via
/// `@AppStorage`), which advances routing to the rating assessment. The
/// visual treatment is an intentional placeholder pending a final design pass.
struct LibraryLoadingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    @State private var progress: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "crown")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                Text("DailyTactics")
                    .font(.title.bold())
                Text("Loading your puzzle library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 240)
                    .tint(.accentColor)
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await PuzzleLibraryImporter(context: modelContext).importAllBundled { value in
                progress = value
            }
            // Flip the first-launch gate. `@AppStorage` in RootView observes
            // this key, so the change re-routes away from this screen.
            libraryImported = true
        }
    }
}
