import SwiftUI

/// The how-to-play note, presented as a popover from the board screen's
/// info button. Four points in a scrolling list so large Dynamic
/// Type stays readable.
struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    /// The points, in reading order. Localized separately so each row can
    /// label itself.
    private var points: [(icon: String, text: String)] {
        [
            ("sparkles", String(localized: "how_to_play.calculate")),
            ("lightbulb", String(localized: "how_to_play.hint")),
            ("clock.arrow.circlepath", String(localized: "how_to_play.rounds")),
            ("eye", String(localized: "how_to_play.review")),
        ]
    }

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
                VStack(alignment: .leading, spacing: 14) {
                    // Array() wrap: EnumeratedSequence gains RandomAccessCollection
                    // conformance only in iOS 26; the target is iOS 17.
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: point.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            Text(point.text)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
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
