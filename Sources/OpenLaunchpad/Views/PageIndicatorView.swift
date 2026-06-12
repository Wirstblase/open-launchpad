import SwiftUI

// MARK: - Page Indicator View

/// A row of dots at the bottom of the screen indicating the current page.
/// Supports tap-to-jump and smooth interpolation during drag/swipe.
struct PageIndicatorView: View {
    let numberOfPages: Int
    let currentPage: Int
    let dragOffset: CGFloat
    let screenWidth: CGFloat
    var onPageTap: ((Int) -> Void)? = nil

    var body: some View {
        let fractionalPage = CGFloat(currentPage) - (dragOffset / max(1.0, screenWidth))

        HStack(spacing: 12) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                let distance = abs(fractionalPage - CGFloat(index))
                let activeProgress = max(0.0, min(1.0, 1.0 - distance))
                let opacity = 0.3 + (activeProgress * 0.7)
                let scale = 1.0 + (activeProgress * 0.25)

                Circle()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: 8, height: 8)
                    .scaleEffect(scale)
                    .animation(.easeOut(duration: 0.2), value: opacity)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture {
                        onPageTap?(index)
                    }
            }
        }
    }
}
