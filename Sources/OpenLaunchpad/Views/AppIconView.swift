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
                    .stroke(Color.green.opacity(0.85), lineWidth: 3)
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
        .rotationEffect(isJiggling ? .degrees(3.5) : .zero)
        .animation(isJiggling ? Animation.easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: isJiggling)
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
            resolvedIcon = renderFolderPreview(folder: folder)
        }
    }

    /// Renders a 3×3 mini-grid preview for folder icons.
    private func renderFolderPreview(folder: AppFolder) -> NSImage? {
        let previewSize = iconSize
        let scale: CGFloat = 2.0  // Retina
        let pixelW = Int(previewSize * scale)
        let pixelH = Int(previewSize * scale)
        let mini = previewSize * 0.24
        let gap = previewSize * 0.05
        let pad = (previewSize - 3 * mini - 2 * gap) / 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: previewSize, height: previewSize)

        // Set up graphics context BEFORE saving state
        let nsContext = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Background rounded rect
        let bgPath = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: previewSize, height: previewSize),
            xRadius: previewSize * 0.225,
            yRadius: previewSize * 0.225
        )
        NSColor.white.withAlphaComponent(0.15).setFill()
        bgPath.fill()

        // Draw up to 9 app icons (3×3 grid, top-to-bottom)
        let iconCount = min(folder.appIDs.count, 9)
        for i in 0..<iconCount {
            let col = CGFloat(i % 3)
            let row = CGFloat(i / 3)
            let x = pad + col * (mini + gap)
            let y = pad + (2 - row) * (mini + gap)  // flip Y: row 0 at top
            let rect = NSRect(x: x, y: y, width: mini, height: mini)

            if let app = appLookup[folder.appIDs[i]] {
                // Use synchronous NSWorkspace icon for reliable drawing
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icon.size = NSSize(width: mini * scale, height: mini * scale)
                icon.draw(in: rect, from: NSRect(x: 0, y: 0, width: icon.size.width, height: icon.size.height),
                          operation: .sourceOver, fraction: 1.0)
            } else {
                // Fallback: draw a small colored placeholder
                let hue = CGFloat(abs(folder.appIDs[i].hashValue) % 256) / 256.0
                NSColor(hue: hue, saturation: 0.5, brightness: 0.7, alpha: 0.6).setFill()
                NSBezierPath(roundedRect: rect, xRadius: mini * 0.2, yRadius: mini * 0.2).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: previewSize, height: previewSize))
        image.addRepresentation(rep)
        return image
    }


}
