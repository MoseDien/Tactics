import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var difficulty = DifficultyModeStore.current
    @State private var showingHowToPlay = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(String(localized: "settings.difficulty"), selection: $difficulty) {
                        ForEach(DifficultyMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.localizedKey)).tag(mode)
                        }
                    }
                    .onChange(of: difficulty) { _, value in
                        DifficultyModeStore.set(value)
                    }
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label(String(localized: "settings.history"), systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(String(localized: "settings.history_footer"))
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
                    .accessibilityLabel(String(localized: "settings.how_to_play"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { dismiss() }
                }
            }
            .alert(String(localized: "settings.how_to_play"), isPresented: $showingHowToPlay) {
                Button(String(localized: "common.got_it"), role: .cancel) { }
            } message: {
                Text(String(localized: "settings.how_to_play_body"))
            }
        }
    }
}
