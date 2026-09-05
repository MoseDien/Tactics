import SwiftUI

/// The app's logo: the wordmark "iTactics" with a red "i" — the same
/// treatment as the storyboard launch screen (crimson sRGB 220,20,60 on the
/// system background). One implementation so the two stay in sync.
struct AppWordmark: View {
    var fontSize: CGFloat = 36

    /// Launch-screen crimson, matching LaunchScreen.storyboard's logo-i.
    private let markRed = Color(red: 220 / 255, green: 20 / 255, blue: 60 / 255)

    var body: some View {
        // Styled-concatenation rather than string interpolation: an
        // interpolated inner Text (`Text("i\(Text("Tactics"))")`) can flatten
        // the inner style, losing the red "i".
        (Text("i") + Text("Tactics").foregroundStyle(.primary))
            .foregroundStyle(markRed)
            .font(.system(size: fontSize, weight: .bold))
    }
}

#Preview("Wordmark") {
    AppWordmark()
        .padding()
}
