import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingHowToPlay = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text("Review completed puzzles grouped into rounds of five.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingHowToPlay = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("How to play")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("How to Play", isPresented: $showingHowToPlay) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("Do not guess your way through a move. Think through the position one move at a time, calculate the opponent's replies, and continue until you win the puzzle.")
            }
        }
    }
}
