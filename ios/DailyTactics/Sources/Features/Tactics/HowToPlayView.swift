import SwiftUI

/// The how-to-play note, presented as a popover from the board screen's
/// info button. Scrolls internally so large Dynamic Type stays readable.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "settings.how_to_play"))
                .font(.headline)

            Text(String(localized: "settings.how_to_play_body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "common.got_it")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    HowToPlayView()
        .frame(minWidth: 320, minHeight: 220)
}
