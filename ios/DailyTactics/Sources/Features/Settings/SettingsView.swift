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
                        Label(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(String(localized: "settings.historyFooter"))
                }
            }
            .navigationTitle(String(localized: "settings.title"))
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
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .alert("How to Play", isPresented: $showingHowToPlay) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("- Do not guess through a move, or do not try with a move, put the whole chessboard in brain, and find a solution in brain. \n- Can play 5 puzzle within an hour.")
            }
        }
    }
}
