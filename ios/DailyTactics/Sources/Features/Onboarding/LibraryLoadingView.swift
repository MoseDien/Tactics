import SwiftUI
import TacticsData

/// First-launch screen that bulk-imports the bundled puzzle chunk into
/// SwiftData. On success it flips the
/// `LibraryStateStore.importedKey` flag (observed by `RootView` via
/// `@AppStorage`), which advances routing to Daily Tactics. If the chunk
/// fails to decode, the flag is *not* flipped — the screen shows an error
/// with a retry instead of silently degrading to the bundled samples.
/// The header is the launch screen's wordmark (see `AppWordmark`), so the
/// import reads as a continuation of app startup.
struct LibraryLoadingView: View {
    @Environment(AppDependencies.self) private var dependencies
    @AppStorage(LibraryStateStore.importedKey) private var libraryImported = false
    @State private var progress: Double = 0
    @State private var failedTiers: Int?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                AppWordmark()
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
            let failures = await dependencies.importer.importAllBundled { value in
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
