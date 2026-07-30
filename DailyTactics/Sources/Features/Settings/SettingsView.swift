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
                    Text("This clears your current baseline rating. Your puzzle progress is kept.")
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
                    PuzzleLibraryImporter(context: modelContext).reset()
                    RatingAssessmentStore(context: modelContext).reset()
                    UserRatingStore().reset()
                    didReset = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current baseline rating will be cleared. Puzzle progress will not be deleted.")
            }
        }
    }
}
