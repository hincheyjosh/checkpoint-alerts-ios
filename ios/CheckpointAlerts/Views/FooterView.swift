import SwiftUI

/// Little sign-off at the bottom of every screen.
struct MadeWithLoveFooter: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Made with")
            CannabisLeafView()
            Text("in mind")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
