import SwiftUI
import TacticsData

/// First-launch bulk import. Flips the import gate on success; a decode
/// failure shows an error + retry instead of silently degrading.
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
                libraryImported = true
            } else {
                failedTiers = failures
            }
        }
    }
}
