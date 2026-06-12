import SwiftUI
import UniformTypeIdentifiers

// MARK: - App Icon View

/// Renders a single app icon on the Launchpad grid.
/// Tap to launch, long-press to enter jiggle mode, drag to reorder or create folders.
struct AppIconView: View {
    let item: LaunchpadItem
    let iconSize: CGFloat
    let isFocused: Bool
    let isJiggling: Bool
    let isMergeTarget: Bool
    let showLabels: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var resolvedIcon: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            // Icon
            ZStack(alignment: .topLeading) {
                iconContent

                // Focus ring (keyboard navigation)
                RoundedRectangle(cornerRadius: iconSize * 0.225 + 2)
                    .stroke(Color.blue.opacity(0.85), lineWidth: 3)
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .opacity(isFocused ? 1.0 : 0.0)

                // Merge target glow (dragging app onto this one for folder creation)
                RoundedRectangle(cornerRadius: iconSize * 0.225 + 3)
                    .stroke(Color.green.opacity(0.85), lineWidth: 3)
                    .frame(width: iconSize + 8, height: iconSize + 8)
                    .scaleEffect(1.12)
                    .opacity(isMergeTarget ? 1.0 : 0.0)

                // Delete badge (jiggle mode)
                if isJiggling {
                    deleteBadge
                }
            }
            .scaleEffect(isMergeTarget ? 1.15 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isMergeTarget)

            // Label
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
                .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
                .opacity(showLabels ? 1.0 : 0.0)
        }
        .frame(width: iconSize + 20)
        .contentShape(Rectangle())
        .accessibilityLabel("\(item.name), \(item.id.hasPrefix("folder-") ? "Folder" : "Application")")
        .accessibilityAddTraits(.isButton)
        .rotationEffect(isJiggling ? jiggleAngle : .zero)
        .animation(
            isJiggling
                ? Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true)
                : .default,
            value: isJiggling
        )
        // Tap
        .simultaneousGesture(
            TapGesture().onEnded {
                onTap()
            }
        )
        // Long-press → enter jiggle mode
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onEnded { _ in
                    onLongPress()
                }
        )
        // Drag to reorder / create folders
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
                .frame(width: iconSize, height: iconSize)
        } else {
            RoundedRectangle(cornerRadius: iconSize * 0.225)
                .fill(Color.white.opacity(0.12))
                .frame(width: iconSize, height: iconSize)
        }
    }

    // MARK: - Delete Badge

    private var deleteBadge: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                }
                .offset(x: 6, y: -6)
            }
            Spacer()
        }
        .onTapGesture {
            // Phase 4: hide app from Launchpad
        }
    }

    // MARK: - Jiggle Angle

    /// Each icon gets a slightly different jiggle phase based on its ID hash.
    private var jiggleAngle: Angle {
        let hash = abs(item.id.hashValue)
        let phase = Double(hash % 100) / 100.0 * .pi * 2
        let amplitude: Double = 1.5
        return .degrees(sin(Date().timeIntervalSinceReferenceDate * 6 + phase) * amplitude)
    }

    // MARK: - Icon Resolution

    private func resolveIcon() async {
        switch item {
        case .app(let app):
            resolvedIcon = await IconCache.shared.icon(for: app)
        case .folder(let folder, _):
            resolvedIcon = await renderFolderPreview(folder: folder)
        }
    }

    /// Renders a 3×3 mini-grid preview for folder icons.
    private func renderFolderPreview(folder: AppFolder) async -> NSImage? {
        let previewSize = iconSize
        let mini = previewSize * 0.24
        let gap = previewSize * 0.05
        let pad = (previewSize - 3 * mini - 2 * gap) / 2

        let image = NSImage(size: NSSize(width: previewSize, height: previewSize))
        image.lockFocus()

        // Background
        let bgPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: previewSize, height: previewSize),
            xRadius: previewSize * 0.225,
            yRadius: previewSize * 0.225
        )
        NSColor.white.withAlphaComponent(0.15).setFill()
        bgPath.fill()

        // Draw up to 9 app icons
        let iconCount = min(folder.appIDs.count, 9)
        for i in 0..<iconCount {
            let col = CGFloat(i % 3)
            let row = CGFloat(i / 3)
            let x = pad + col * (mini + gap)
            let y = pad + (2 - row) * (mini + gap)  // top-to-bottom
            let rect = NSRect(x: x, y: y, width: mini, height: mini)

            // Try to load cached icon for the app
            if let app = folderApp(for: folder.appIDs[i]) {
                let icon = await IconCache.shared.icon(for: app)
                icon.draw(in: rect)
            }
        }

        image.unlockFocus()
        return image
    }

    /// Looks up an AppItem by ID from a quick scan. Inefficient but called rarely.
    private func folderApp(for appID: String) -> AppItem? {
        // We can't easily look this up without access to all apps.
        // The caller should provide the app list. For now, return nil.
        // Phase 4 refinement: pass app lookup dictionary.
        nil
    }
}
