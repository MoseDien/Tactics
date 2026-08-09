import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showResetConfirmation = false
    @State private var didReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Reassess baseline rating", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityHint("Clears your baseline rating and starts the rating assessment again")
                } footer: {
                    Text("Clears your baseline rating and puzzle progress. Your imported puzzle library is kept.")
                }

                if didReset {
                    Section {
                        Label("Baseline rating reset. The assessment will be shown on the next launch.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Reassess baseline rating?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reassess", role: .destructive) {
                    // Keep the imported puzzle library (re-importing ~10k rows is
                    // expensive); only clear runtime progress so puzzles become
                    // unattempted again, then re-run the assessment.
                    PuzzleLibraryImporter(context: modelContext).resetProgress()
                    RatingAssessmentStore(context: modelContext).reset()
                    UserRatingStore().reset()
                    didReset = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your baseline rating and puzzle progress will be cleared so you can reassess. Your puzzle library is kept.")
            }
        }
    }
}

