import SwiftUI

/// The how-to-play note, presented as a popover from the board screen's
/// info button. The body scrolls so large Dynamic Type stays readable.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "settings.how_to_play"))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .accessibilityLabel(String(localized: "common.done"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView {
                Text(String(localized: "settings.how_to_play_body"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            HStack {
                Spacer()
                Button(String(localized: "common.got_it")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
    }
}

#Preview {
    HowToPlayView()
        .frame(minWidth: 320, minHeight: 260)
}
