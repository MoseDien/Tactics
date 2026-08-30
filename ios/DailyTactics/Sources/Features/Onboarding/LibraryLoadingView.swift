import SwiftUI
import SwiftData

/// First-launch screen that bulk-imports the entire bundled puzzle library
/// (all 10 rating tiers) into SwiftData. On success it flips the
/// `LibraryStateStore.importedKey` flag (observed by `RootView` via
/// `@AppStorage`), which advances routing to Daily Tactics. If any tier fails
/// to decode, the flag is *not* flipped — the screen shows an error with a
/// retry instead of silently degrading to the bundled samples.
/// visual treatment is an intentional placeholder pending a final design pass.
struct LibraryLoadingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    @State private var progress: Double = 0
    @State private var failedTiers: Int?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "crown")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                Text(String(localized: "app.name"))
                    .font(.title.bold())
                if failedTiers == nil {
                    Text(String(localized: "loading.library"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                        .tint(.accentColor)
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "loading.library_failed"))
                        .font(.subheadline)
                        .foregroundStyle(.red)
                    Button(String(localized: "common.retry")) {
                        failedTiers = nil
                        progress = 0
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task(id: failedTiers) {
            guard failedTiers == nil else { return }
            let failures = await PuzzleLibraryImporter(context: modelContext).importAllBundled { value in
                progress = value
            }
            if failures == 0 {
                // Flip the first-launch gate. `@AppStorage` in RootView observes
                // this key, so the change re-routes away from this screen.
                libraryImported = true
            } else {
                failedTiers = failures
            }
        }
    }
}
