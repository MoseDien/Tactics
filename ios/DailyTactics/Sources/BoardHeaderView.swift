import SwiftUI

/// The same warm tone the boards paint light squares with.
private let boardHeaderLightSquare = Color(red: 0.94, green: 0.85, blue: 0.70)

/// The band every board screen crowns its board with: the side's king on a
/// warm light-square tile, a two-line context stack (title over subtitle),
/// and a trailing accessory each screen supplies — difficulty stars on the
/// training board, rating/stars/theme on the review sheets, the material
/// badge on the analysis board.
struct BoardHeaderView<Accessory: View>: View {
    let kingAsset: String
    let title: String?
    var subtitle: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    init(
        kingAsset: String,
        title: String?,
        subtitle: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.kingAsset = kingAsset
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack {
                Image(kingAsset)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: 54, height: 54)
                    .background(boardHeaderLightSquare)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    if let title {
                        Text(title)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)

            accessory()
        }
        .padding(8)
        .background(Color(.secondarySystemBackground).opacity(0.72))
        .clipShape(.rect(cornerRadius: 16))
    }
}
