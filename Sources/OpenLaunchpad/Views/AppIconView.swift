import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Icon View

/// Renders a single app icon on the Launchpad grid.
/// Tap to launch, long-press to enter jiggle mode, drag to reorder or create folders.
/// Performance note: jiggle animation is driven by a shared angle computed once
/// per frame in the parent view — NOT by per-icon .repeatForever animations.
struct AppIconView: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let isFocused: Bool
    let isJiggling: Bool
    let jiggleAngle: Double       // Shared angle from parent's TimelineView
    let isMergeTarget: Bool
    let showLabels: Bool
    let appLookup: [String: AppItem]
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var resolvedIcon: NSImage?
    @State private var isPressed = false

    // MARK: - Layout Constants

    private var labelSpacing: CGFloat { 6 }
    private var iconCornerRadius: CGFloat { iconSize * 0.225 }
    private var labelFrameHeight: CGFloat { 28 }
    private var labelWidthOffset: CGFloat { 20 }

    var body: some View {
        VStack(spacing: labelSpacing) {
            // Icon
            ZStack(alignment: .center) {
                iconContent

                // Focus ring (keyboard navigation)
                RoundedRectangle(cornerRadius: iconCornerRadius + 2)
                    .stroke(Color.blue.opacity(0.85), lineWidth: 3)
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .opacity(isFocused ? 1.0 : 0.0)

                // Merge target glow (dragging app onto this one for folder creation)
                RoundedRectangle(cornerRadius: iconCornerRadius + 3)
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: iconSize + 8, height: iconSize + 8)
                    .scaleEffect(1.12)
                    .opacity(isMergeTarget ? 1.0 : 0.0)

            }
            .scaleEffect(isMergeTarget ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isMergeTarget)

            // Label
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: iconSize + labelWidthOffset, height: labelFrameHeight, alignment: .top)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                .opacity(showLabels ? 1.0 : 0.0)
        }
        .frame(width: iconSize + labelWidthOffset)
        .contentShape(Rectangle())
        .overlay(Color.black.opacity(isPressed ? 0.35 : 0))
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .accessibilityLabel("\(item.name), \(item.id.hasPrefix("folder-") ? "Folder" : "Application")")
        .accessibilityHint(item.id.hasPrefix("folder-") ? "Double-tap to open folder" : "Double-tap to launch application")
        .accessibilityAddTraits(.isButton)
        // Jiggle: use shared angle from parent TimelineView — NO per-icon .repeatForever
        .rotationEffect(.degrees(isJiggling ? jiggleAngle : 0))
        // Tap with visual feedback
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { isPressed = false }
            onTap()
        }
        // Drag to move icons (only useful in edit mode; ignored when not jiggling)
        .onDrag {
            NSItemProvider(object: item.id as NSString)
        }
        // Resolve icon
        .task {
            await resolveIcon()
        }
    }

    // MARK: - Icon Content

    @ViewBuilder
    private var iconContent: some View {
        if let icon = resolvedIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        } else {
            RoundedRectangle(cornerRadius: iconCornerRadius)
                .fill(Color.white.opacity(0.12))
                .frame(width: iconSize, height: iconSize)
        }
    }

    // MARK: - Icon Resolution

    private func resolveIcon() async {
        switch item {
        case .app(let app):
            resolvedIcon = await IconCache.shared.icon(for: app)
        case .folder(let folder, _):
            resolvedIcon = await IconCache.shared.folderPreview(
                folderID: folder.id.uuidString,
                appIDs: folder.appIDs,
                size: iconSize
            )
        }
    }
}
