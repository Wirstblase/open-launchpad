import SwiftUI

// MARK: - Search Bar View

/// A text field styled like the classic Launchpad search bar.
/// Appears as a capsule at the top of the screen when activated.
struct SearchBarView: View {
    @Binding var text: String
    @FocusState var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 13, weight: .medium))

            TextField("Search", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: 320)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.45))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
